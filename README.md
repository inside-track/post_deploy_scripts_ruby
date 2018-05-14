# PostDeployScriptsRuby

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/post_deploy_scripts_ruby`. To experiment with that code, run `bin/console` for an interactive prompt.

```bash
$ bundle exec rake pds:create test
Generated post_deploy_scripts/20180514235303_test.rb
$ bundle exec rake pds:run
== 20180514234224 Test: running ===============================================
== 20180514234224 Test: ran (0.0000s) =========================================
$ bundle exec rake pds:revert
== 20180514234224 Test: reverting =============================================
== 20180514234224 Test: reverted (0.0000s) ====================================
```

Running scripts with explicit schema change methods will cause an error.  Create the script with the -s or -schema flag to circumvent this.
Or manual add this method to a script:

```ruby
def allow_explicit_schema_changes?
    true
end
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'post_deploy_scripts_ruby'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install post_deploy_scripts_ruby

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/post_deploy_scripts_ruby.
