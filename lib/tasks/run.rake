namespace :pds do

  desc "Run pending post deploy scripts."
  task run: [:environment, :load_config] do
    begin
      verbose = ENV["VERBOSE"] ? ENV["VERBOSE"] == "true" : true
      version = ENV["VERSION"] ? ENV["VERSION"].to_i : nil
      scope   = ENV['SCOPE']
      verbose_was, PostDeployScripts::Script.verbose = PostDeployScripts::Script.verbose, verbose
      PostDeployScripts::Migrator.migrate("post_deploy_scripts", version) do |migration|
        scope.blank? || scope == migration.scope
      end
      Rake::Task['db:_dump'].invoke if ActiveRecord::Base.dump_schema_after_migration
    ensure
      PostDeployScripts::Script.verbose = verbose_was
    end
  end

  namespace :run do
    # desc  'Reverts the by one script and re runs (options: STEP=x, VERSION=x).'
    task :redo => [:environment, :load_config] do
      if ENV['VERSION']
        Rake::Task['pds:run:down'].invoke
        Rake::Task['pds:run:up'].invoke
      else
        Rake::Task['pds:revert'].invoke
        Rake::Task['pds:run'].invoke
      end
    end

    # desc 'Runs the "up" for a given script VERSION.'
    task :up => [:environment, :load_config] do
      version = ENV['VERSION'] ? ENV['VERSION'].to_i : nil
      raise 'VERSION is required' unless version
      PostDeployScripts::Migrator.run(:up, PostDeployScripts::Migrator.migrations_paths, version)
      Rake::Task['db:_dump'].invoke if ActiveRecord::Base.dump_schema_after_migration
    end

    # desc 'Runs the "down" for a given script VERSION.'
    task :down => [:environment, :load_config] do
      version = ENV['VERSION'] ? ENV['VERSION'].to_i : nil
      raise 'VERSION is required' unless version
      PostDeployScripts::Migrator.run(:down, PostDeployScripts::Migrator.migrations_paths, version)
      Rake::Task['db:_dump'].invoke
    end
  end
end