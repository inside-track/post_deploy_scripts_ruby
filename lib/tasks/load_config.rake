
if defined?(Rails)
  namespace :pds do
    task :load_config do
      ActiveRecord::Tasks::DatabaseTasks.database_configuration = Rails.application.config.database_configuration
    end
  end
else
  namespace :pds do
    task :load_config do
      Rake::Task["db:load_config"].invoke
    end
  end
  Rake::Task.define_task("pds:environment")
end