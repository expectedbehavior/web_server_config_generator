require 'rubygems'
gem 'hoe', '>= 2.1.0'
require 'hoe'
require 'fileutils'
require './lib/web_server_config_generator'

Hoe.plugin :newgem
# Hoe.plugin :website
# Hoe.plugin :cucumberfeatures

# Generate all the Rake tasks
# Run 'rake -T' to see list of generated tasks (from gem root directory)
$hoe = Hoe.spec 'web_server_config_generator' do
  self.developer 'Jason Gladish', 'jason@expectedbehavior.com'
  self.post_install_message = 'PostInstall.txt' # TODO remove if post-install message not required
  self.rubyforge_name       = self.name # TODO this is default value
  # self.extra_deps         = [['activesupport','>= 2.0.2']]

end

require 'newgem/tasks'
Dir['tasks/**/*.rake'].each { |t| load t }

# TODO - want other tests/tasks run by default? Add them to the list
# remove_task :default
# task :default => [:spec, :features]

# hoe's test task globs too much and includes test example app files
remove_task :test
Rake::TestTask.new :test do |t|
  t.libs << "test"
  t.test_files = FileList['test/test*.rb']
  t.verbose = true
end

unless ENV['NO_DEBUG']
  require 'ruby-debug'
  Debugger.start
  rc_file = File.join(File.dirname(File.dirname(__FILE__)), 'rdebugrc')
  Debugger.run_script rc_file if File.exists?(rc_file)
end

