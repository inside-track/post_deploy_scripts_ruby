module PostDeployScripts
  class Railtie < Rails::Railtie
    rake_tasks do
      load 'tasks/load_config.rake'
      load 'tasks/create.rake'
      load 'tasks/revert.rake'
      load 'tasks/run.rake'
    end

  end
end