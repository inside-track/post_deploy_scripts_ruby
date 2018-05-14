unless Rake::Task.task_defined?("db:create")
  load "active_record/railties/databases.rake"
end

load 'tasks/load_config.rake'
load 'tasks/create.rake'
load 'tasks/revert.rake'
load 'tasks/run.rake'