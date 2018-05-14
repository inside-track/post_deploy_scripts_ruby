require "active_support/core_ext/module/attribute_accessors"
require 'set'

if ActiveRecord::VERSION::STRING.to_f < 5
  class ActiveRecord::Migration
    def self.[](version)
      self
    end
  end
end

module PostDeployScripts
  class PostDeployScriptError < ActiveRecord::ActiveRecordError#:nodoc:
    def initialize(message = nil)
      message = "\n\n#{message}\n\n" if message
      super
    end
  end

  class DuplicateScriptVersionError < PostDeployScriptError#:nodoc:
    def initialize(version)
      super("Multiple migrations have the version number #{version}")
    end
  end

  class DuplicateScriptNameError < PostDeployScriptError#:nodoc:
    def initialize(name)
      super("Multiple migrations have the name #{name}")
    end
  end

  class UnknownScriptVersionError < PostDeployScriptError #:nodoc:
    def initialize(version)
      super("No migration with version number #{version}")
    end
  end

  class ExplicitSchemaChangeError < PostDeployScriptError #:nodoc:
    def initialize(message = nil)
      message = "\n\n#{message}\n\n" if message
      super
    end
  end

  class IllegalScriptNameError < PostDeployScriptError#:nodoc:
    def initialize(name)
      super("Illegal name for migration file: #{name}\n\t(only lower case letters, numbers, and '_' allowed)")
    end
  end

  class PendingPostDeployScriptError < PostDeployScriptError#:nodoc:
    def initialize
      if defined?(Rails)
        super("Post deploy scripts are pending. To resolve this issue, run:\n\n\tbin/rake db:migrate RAILS_ENV=#{::Rails.env}")
      else
        super("Post deploy scripts are pending. To resolve this issue, run:\n\n\tbin/rake db:migrate")
      end
    end
  end

  class Script < ActiveRecord::Migration[ActiveRecord::VERSION::STRING.to_f]

    class CheckPending
      def initialize(app)
        @app = app
        @last_check = 0
      end

      def call(env)
        if connection.supports_migrations?
          mtime = PostDeployScripts::Migrator.last_migration.mtime.to_i
          if @last_check < mtime
            PostDeployScripts::Script.check_pending!(connection)
            @last_check = mtime
          end
        end
        @app.call(env)
      end

      private

      def connection
        ActiveRecord::Base.connection
      end
    end

    class << self
      attr_accessor :delegate # :nodoc:
      attr_accessor :disable_ddl_transaction # :nodoc:

      def check_pending!(connection = ActiveRecord::Base.connection)
        raise PostDeployScripts::PendingPostDeployScriptError if PostDeployScripts::Migrator.needs_migration?(connection)
      end

      def load_schema_if_pending!
        if PostDeployScripts::Migrator.needs_migration? || !PostDeployScripts::Migrator.any_migrations?
          # Roundrip to Rake to allow plugins to hook into database initialization.
          FileUtils.cd Rails.root do
            current_config = ActiveRecord::Base.connection_config
            ActiveRecord::Base.clear_all_connections!
            system("bin/rake db:test:prepare")
            # Establish a new connection, the old database may be gone (db:test:prepare uses purge)
            ActiveRecord::Base.establish_connection(current_config)
          end
          check_pending!
        end
      end

      def maintain_test_schema! # :nodoc:
        if ActiveRecord::Base.maintain_test_schema
          suppress_messages { load_schema_if_pending! }
        end
      end

      def explicit_schema_change?(method_name)
        !non_explicit_schema_change_methods.include?(method_name)
      end

      def non_explicit_schema_change_methods
        @non_explicit_schema_change_methods ||= [
          :add_index, :remove_index, :execute_block,
          :execute, :enable_extension, :disable_extension
        ]
      end

    end

    cattr_accessor :verbose
    attr_accessor :name, :version

    def initialize(name = self.class.name, version = nil)
      @name       = name
      @version    = version
      @connection = nil
    end

    self.verbose = true
    # instantiate the delegate object after initialize is defined
    self.delegate = new

    class ReversibleBlockHelper < Struct.new(:reverting) # :nodoc:
      def up
        yield unless reverting
      end

      def down
        yield if reverting
      end
    end

    def reversible
      raise RuntimeError, "reversible method is not available"
      # helper = ReversibleBlockHelper.new(reverting?)
      # execute_block{ yield helper }
    end

    # Execute this migration in the named direction
    def migrate(direction)
      return unless respond_to?(direction)

      case direction
      when :up   then announce "running"
      when :down then announce "reverting"
      end

      time   = nil
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        time = Benchmark.measure do
          exec_migration(conn, direction)
        end
      end

      case direction
      when :up   then announce "ran (%.4fs)" % time.real; write
      when :down then announce "reverted (%.4fs)" % time.real; write
      end
    end

    def connection
      @connection || ActiveRecord::Base.connection
    end

    def method_missing(method, *arguments, &block)
      arg_list = arguments.map{ |a| a.inspect } * ', '

      say_with_time "#{method}(#{arg_list})" do
        unless @connection.respond_to? :revert
          unless arguments.empty? || [:execute, :enable_extension, :disable_extension].include?(method)
            arguments[0] = proper_table_name(arguments.first, table_name_options)
            if [:rename_table, :add_foreign_key].include?(method)
              arguments[1] = proper_table_name(arguments.second, table_name_options)
            end
          end
        end
        return super unless connection.respond_to?(method)
        if allow_explicit_schema_changes? || !self.class.explicit_schema_change?(method)
          connection.send(method, *arguments, &block)
        else
          raise ExplicitSchemaChangeError, "Looks like you might be trying to execute a schema change.\nSchema changes should be performed in a migration.\n\n To override this behavior call `allow_explicit_schema_changes!` prior to executed schema changes."
        end
      end
    end

    def copy(destination, sources, options = {})
      copied = []

      FileUtils.mkdir_p(destination) unless File.exist?(destination)

      destination_migrations = PostDeployScripts::Migrator.migrations(destination)
      last = destination_migrations.last
      sources.each do |scope, path|
        source_migrations = PostDeployScripts::Migrator.migrations(path)

        source_migrations.each do |migration|
          source = File.binread(migration.filename)
          inserted_comment = "# This script comes from #{scope} (originally #{migration.version})\n"
          if /\A#.*\b(?:en)?coding:\s*\S+/ =~ source
            # If we have a magic comment in the original migration,
            # insert our comment after the first newline(end of the magic comment line)
            # so the magic keep working.
            # Note that magic comments must be at the first line(except sh-bang).
            source[/\n/] = "\n#{inserted_comment}"
          else
            source = "#{inserted_comment}#{source}"
          end

          if duplicate = destination_migrations.detect { |m| m.name == migration.name }
            if options[:on_skip] && duplicate.scope != scope.to_s
              options[:on_skip].call(scope, migration)
            end
            next
          end

          migration.version = next_migration_number(last ? last.version + 1 : 0).to_i
          new_path = File.join(destination, "#{migration.version}_#{migration.name.underscore}.#{scope}.rb")
          old_path, migration.filename = migration.filename, new_path
          last = migration

          File.binwrite(migration.filename, source)
          copied << migration
          options[:on_copy].call(scope, migration, old_path) if options[:on_copy]
          destination_migrations << migration
        end
      end

      copied
    end

    def exec_migration(conn, direction)
      @connection = conn
      send(direction)
    ensure
      @connection = nil
    end

    private

    def allow_explicit_schema_changes?
      false
    end

    def explicit_schema_change_message
      <<~MESSAGE
      Looks like you might be trying to execute a schema change.
      Schema changes should be performed in a migration.
      To override this behavior define the method `allow_explicit_schema_changes?` returning a truthy value.
      MESSAGE
    end

  end

  # MigrationProxy is used to defer loading of the actual migration classes
  # until they are needed
  class MigrationProxy < Struct.new(:name, :version, :filename, :scope)

    def initialize(name, version, filename, scope)
      super
      @migration = nil
    end

    def basename
      File.basename(filename)
    end

    def mtime
      File.mtime filename
    end

    delegate :migrate, :announce, :write, :disable_ddl_transaction, to: :migration

    private

      def migration
        @migration ||= load_migration
      end

      def load_migration
        require(File.expand_path(filename))
        name.constantize.new(name, version)
      end

  end

  class NullMigration < MigrationProxy #:nodoc:
    def initialize
      super(nil, 0, nil, nil)
    end

    def mtime
      0
    end
  end

  class Migrator < ActiveRecord::Migrator
    class << self

      def schema_migrations_table_name
        PreviouslyRunScript.table_name
      end

      def get_all_versions(connection = ActiveRecord::Base.connection)
        if connection.table_exists?(schema_migrations_table_name)
          PreviouslyRunScript.all.map { |x| x.version.to_i }.sort
        else
          []
        end
      end

      def last_migration #:nodoc:
        migrations(migrations_paths).last || NullMigration.new
      end

      def migrations_paths
        @migrations_paths ||= ['post_deploy_scripts']
      end

      def migrations(paths)
        paths = Array(paths)

        files = Dir[*paths.map { |p| "#{p}/**/[0-9]*_*.rb" }]

        migrations = files.map do |file|
          version, name, scope = file.scan(/([0-9]+)_([_a-z0-9]*)\.?([_a-z0-9]*)?\.rb\z/).first

          raise IllegalScriptNameError.new(file) unless version
          version = version.to_i
          name = name.camelize

          MigrationProxy.new(name, version, file, scope)
        end

        migrations.sort_by(&:version)
      end
    end

    def initialize(direction, migrations, target_version = nil)

      @direction         = direction
      @target_version    = target_version
      @migrated_versions = nil
      @migrations        = migrations

      validate(@migrations)

      PreviouslyRunScript.create_table
    end

    def run
      migration = migrations.detect { |m| m.version == @target_version }
      raise UnknownScriptVersionError.new(@target_version) if migration.nil?
      unless (up? && migrated.include?(migration.version.to_i)) || (down? && !migrated.include?(migration.version.to_i))
        begin
          execute_migration_in_transaction(migration, @direction)
        rescue => e
          canceled_msg = use_transaction?(migration) ? ", this migration was canceled" : ""
          raise StandardError, "An error has occurred#{canceled_msg}:\n\n#{e}", e.backtrace
        end
      end
    end

    def migrate
      if !target && @target_version && @target_version > 0
        raise UnknownScriptVersionError.new(@target_version)
      end

      runnable.each do |migration|
        ActiveRecord::Base.logger.info "Running scripts to #{migration.name} (#{migration.version})" if ActiveRecord::Base.logger

        begin
          execute_migration_in_transaction(migration, @direction)
        rescue => e
          canceled_msg = use_transaction?(migration) ? "this and " : ""
          raise StandardError, "An error has occurred, #{canceled_msg}all later scripts canceled:\n\n#{e}", e.backtrace
        end
      end
    end

    private

    def validate(migrations)
      name ,= migrations.group_by(&:name).find { |_,v| v.length > 1 }
      raise DuplicateScriptNameError.new(name) if name

      version ,= migrations.group_by(&:version).find { |_,v| v.length > 1 }
      raise DuplicateScriptVersionError.new(version) if version
    end

    def record_version_state_after_migrating(version)
      if down?
        migrated.delete(version)
        PreviouslyRunScript.where(:version => version.to_s).delete_all
      else
        migrated << version
        PreviouslyRunScript.create!(:version => version.to_s)
      end
    end

    # Wrap the migration in a transaction only if supported by the adapter.
    def ddl_transaction(migration)
      if use_transaction?(migration)
        ActiveRecord::Base.transaction { yield }
      else
        yield
      end
    end

    def use_transaction?(migration)
      !migration.disable_ddl_transaction && ActiveRecord::Base.connection.supports_ddl_transactions?
    end
  end
end
