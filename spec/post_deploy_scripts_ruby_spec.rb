RSpec.describe PostDeployScriptsRuby do
  it "has a version number" do
    expect(PostDeployScriptsRuby::VERSION).not_to be nil
  end

  it "does something useful" do
    expect(false).to eq(true)
  end
end

require 'spec_helper'
require 'fileutils'

class PostDeployScripts::Script
  def migrate_with_quietness(*args)
    suppress_messages do
      migrate_without_quietness(*args)
    end
  end
  alias_method_chain :migrate, :quietness
end

RSpec.describe "the rake tasks" do
  before do
    ActiveRecord::Base.establish_connection(
      adapter: 'sqlite3',
      database: 'db/test.sqlite3'
      pool: 5,
      timeout: 5000
    )

    FileUtils.mkdir_p "db"

    require 'rake'
    require 'post_deploy_scripts_ruby/rake'

    class Rake::Task
      def invoke_with_reenable
        invoke_without_reenable
        reenable
      end
      alias_method_chain :invoke, :reenable
    end
  end

  after do
    FileUtils.rm_rf "db"
  end

  it "creates a script and `post_deploy_scripts` directory" do
    FileUtils.rm_rf("post_deploy_scripts")
    Rake::Task["pds:create"].invoke
    Rake::Task["db:create_migration"].invoke
    Rake::Task["db:migrate"].invoke
    Rake::Task["db:migrate:redo"].invoke
    Rake::Task["db:reset"].invoke
    Rake::Task["db:seed"].invoke

    ENV.delete("NAME")
  end
end
