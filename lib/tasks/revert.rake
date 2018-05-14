namespace :pds do

  desc "Revert the last previously run post deploy script."
  task revert: [:environment, :load_config] do
    step = ENV['STEP'] ? ENV['STEP'].to_i : 1
    PostDeployScripts::Migrator.rollback(PostDeployScripts::Migrator.migrations_paths, step)
    Rake::Task['db:_dump'].invoke
  end
end