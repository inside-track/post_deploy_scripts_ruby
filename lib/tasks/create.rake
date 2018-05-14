require "pathname"
require "fileutils"

namespace :pds do

  desc "Create a post deploy script."
  task :create do
    ARGV.each { |a| task a.to_sym do ; end }
    unless ARGV[1]
      puts "No name specified. Example usage: `rake pds:create <name>`"
      exit
    end



    allow_schema_change = ['-s', '-schema'].include?(ARGV[2])
    name    = ARGV[1]
    version = Time.now.utc.strftime("%Y%m%d%H%M%S")
    directory = "post_deploy_scripts"

    if File.exist?(directory)
      scripts = Pathname(directory).children
      if duplicate = scripts.find { |path| path.basename.to_s =~ /^\w{14}_#{name}.rb$/ }
        puts "Another post deploy script is already named \"#{name}\": #{duplicate}."
        exit
      end
    end

    filename = "#{version}_#{name}.rb"
    dirname  = directory
    path     = File.join(dirname, filename)
    base     = "PostDeployScripts::Script"

    FileUtils.mkdir_p(directory)

    File.write path, if allow_schema_change
      <<~SCRIPT
        class #{name.camelize} < #{base}
          def up
          end

          def down
          end

          private

          def allow_explicit_schema_changes?
            #{allow_schema_change}
          end
        end
      SCRIPT
    else
      <<~SCRIPT
        class #{name.camelize} < #{base}
          def up
          end

          def down
          end
        end
      SCRIPT
    end

    puts "Generated #{path}"
  end
end