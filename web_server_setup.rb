#!/usr/bin/env ruby

require 'fileutils'
require 'pp'
require 'find'
require 'digest/sha1'
require 'pathname'
require 'getoptlong'
require 'rubygems'
require 'highline/import'

opts = GetoptLong.new(*[
                      [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
                      [ '--environment', '-e', GetoptLong::REQUIRED_ARGUMENT ],
                      [ '--hosts', '-n', GetoptLong::NO_ARGUMENT ],
                      [ '--create-web-server-files-dir', '-c', GetoptLong::NO_ARGUMENT ],
                      [ '--verbose', '-v', GetoptLong::NO_ARGUMENT ],
                      [ '--test-mode', '-t', GetoptLong::NO_ARGUMENT ],
                      ]
                      )

$ENVS = []

opts.each do |opt, arg|
  case opt
  when '--environment'
    $ENVS << arg
  when '--hosts'
    $PRINT_HOSTS = true
  when '--create-web-server-files-dir'
    $CREATE_WEB_SERVER_FILES_DIR = true
  when '--verbose'
    $VERBOSE = true
  when '--test-mode'
    $TEST_MODE = true
  else
    puts <<-STR
Usage: #{File.basename(__FILE__)} [project(s) dir] [OPTION]

This will generate web server configuration files for your projects.

If you supply a project directory we assume you have run this before and will just generate the files for that project.  If you specify your projects directory we will generate the files for all projects found.  Not supplying a directory is the same as supplying your current directory.

No flags = try to generate files for all envs

  -e <env> specify a specific environment to generate (defaults to all in database.yml)
  -c       create web_server_files directory (useful the first time you run this script)
           in this case the supplied (or assumed) directory will be set as the 'projects' directory
  -t       test mode; do not modify the FS, just print messsages

  -h       this help screen

    STR
    exit 0
  end
end

def agree( yes_or_no_question, character = nil )
  ask(yes_or_no_question, lambda { |yn| yn.downcase[0] == ?y}) do |q|
    q.validate                 = /\Ay(?:es)?|no?\Z/i
    q.responses[:not_valid]    = 'Please enter "yes" or "no".'
    q.responses[:ask_on_error] = :question
    q.character                = character
    yield q if block_given?
  end
end

class ProjectDirectory < Pathname
  def path
    self
  end
  
  def +(other)
    other = self.class.new(other) unless self.class === other
    self.class.new(plus(@path, other.to_s))
  end

  def file_path_split
    return [path] if path.parent.expand_path == path.expand_path
    self.class.new(path.parent.expand_path).file_path_split + [path.basename]
  end

  def project_directory?
    File.exist? File.join(path, "config", "environment.rb") and
      not path.symlink?
  end

  def directory_contents(path = self, with_directory = true)
    self.class.new(path).children(with_directory)
  end
  
  def possible_project_directory?
    self.directory? and
      self.basename.to_s != $web_server_files_dir_name and
      self.file_path_split.size - $projects_dir.file_path_split.size <= 3 # don't want rails apps that are part of tests or whatever
  end
  
  def child_possible_project_directories
    children.select do |filename|
      filename.possible_project_directory?
    end
  end

  def symlink_directory?
    contents = directory_contents(path)
    contents.any? and contents.all? { |p| FileTest.symlink? p }
  end

  def projects_directory?
    directory_contents(path, false).map { |p| p.to_s }.include? $web_server_files_dir_name
  end

  def find_projects_dir
    return path if path.projects_directory?
    self.parent.expand_path.find_projects_dir unless path.parent.expand_path == path.expand_path
  end

  def environments
    Dir[path.to_s + "/config/environments/*.rb"].map { |p| File.basename(p).gsub(/\.rb/, '') }
  end

  def project_path_from_symlink
    self.class.new(path).realpath.dirname
  end
  
  def without(path)
    self.to_s.sub(path, '')
  end
  
  def projects_relative_path
    self.without($projects_dir).sub(/^\//, '')
  end
  
  def project_name
    projects_relative_path.gsub(/\W/, '-')
  end

  def project_config_files_contents
    config_contents = ""
    config_dir = File.join(self, "config")
    Find.find(config_dir) do |path|
      config_contents << File.open(path) { |f| f.read } if File.file? path
    end
    config_contents
  end
  
  def mkpath
    if $TEST_MODE
      puts "test mode: mkpath #{self}"
    else
      super
    end
  end
  
  def symlink_to_target(target)
    if $TEST_MODE
      puts "test mode: symlink_to_target #{self} -> #{target}"
    else
      File.symlink target, self.expand_path
    end
  end
  
  def write(arg)
    if $TEST_MODE
      puts "test mode: write #{self}, #{arg.to_s[0, 100]}..."
    else
      self.open("w") { |f| f.write arg }
    end
  end
end

$web_server_files_dir_name = "web_server_files"

project_or_projects_dir = ProjectDirectory.new(ARGV.first ? File.expand_path(ARGV.first) : FileUtils.pwd)
if $CREATE_WEB_SERVER_FILES_DIR
  $projects_dir = project_or_projects_dir
else
  unless $projects_dir = project_or_projects_dir.find_projects_dir
    puts "Couldn't find projects dir from #{project_or_projects_dir}"
    if agree("Set #{project_or_projects_dir} to be your projects directory? [Y/n]") { |q| q.default = "Y"}
      $projects_dir = project_or_projects_dir
    else
      puts "exiting..."
      exit 1
    end
  end
end

$web_server_files_dir = $projects_dir + $web_server_files_dir_name
$web_server_links_dir = $web_server_files_dir + "links"
$web_server_vhost_dir = $web_server_files_dir + "vhost"
$web_server_vhost_nginx_dir = $web_server_vhost_dir + "nginx"
$web_server_vhost_nginx_conf = $web_server_vhost_nginx_dir + "projects.conf"

$starting_port = 40000
$port_pool_size = 10000

FileUtils.cd $projects_dir

project_dirs = []
symlink_dirs = []

# setup seed dirs
possible_project_dirs = project_or_projects_dir.project_directory? ? [project_or_projects_dir] : project_or_projects_dir.child_possible_project_directories

# classify and recurse through possiblities
while possible_project_dir = possible_project_dirs.shift
  if possible_project_dir.project_directory?
    project_dirs << possible_project_dir
  elsif possible_project_dir.symlink_directory?
    symlink_dirs << possible_project_dir
  elsif possible_project_dir.symlink?
    # ignore symlinks
  else
    # look in that dir for project directories
    possible_project_dirs += possible_project_dir.child_possible_project_directories
  end
end

# find all environments
if $ENVS.any?
  $environment_map = Hash.new($ENVS)
else
  $environment_map = project_dirs.inject({}) { |m, o| m[o.realpath] = o.environments; m }
  symlink_env_map = symlink_dirs.inject({}) do |m, symlink_dir|
    envs = symlink_dir.children.map { |p| p.realpath.parent.environments }.flatten.uniq
    m[symlink_dir.realpath] = $ENVS.any? ? $ENVS : envs.uniq
    m
  end
  $environment_map.merge! symlink_env_map
end
$environments = $environment_map.values.flatten.uniq

def server_name_from_project_dir_and_env(dir, env)
  "#{dir.project_name}_#{env}.local"
end

def server_names
  $environment_map.map do |dir, envs|
    envs.map do |env|
      server_name_from_project_dir_and_env(dir, env)
    end
  end.flatten
end

if $PRINT_HOSTS
  puts server_names.join("\n")
  exit 0
end

begin
  require 'ghost'
  if agree("Setup ghost entries for projects? [Y/n]") { |q| q.default = "Y"}
    current_hosts = Host.list
    already_correct = []
    added = []
    present_but_incorrect = []
    server_names.each do |server_name|
      if host = current_hosts.detect { |h| h.name == server_name }
        if host.ip == "127.0.0.1"
          already_correct << host
        else
          present_but_incorrect << host
        end
      else
        added << Host.add(server_name)
      end
    end
    
    if already_correct.size > 0
      puts "\n#{already_correct.size} hosts were already setup correctly"
      puts
    end
    
    if added.size > 0
      puts "The following hostnames were added for 127.0.0.1:"
      puts added.map { |h| "  #{h.name}\n" }
      puts
    end
    
    if present_but_incorrect.size > 0
      puts "The following hostnames were present, but didn't map to 127.0.0.1:"
      pad = present_but_incorrect.max{|a,b| a.to_s.length <=> b.to_s.length }.to_s.length
      puts present_but_incorrect.map { |h| "#{h.name.rjust(pad+2)} -> #{h.ip}\n" }
      puts
    end
    
  end
rescue LoadError
  puts "Couldn't load ghost so I won't add hostname entries for you.  Install the 'ghost' gem, or run me with a -n to get a list of hostnames to setup youself."
end


# setup web_server_links_dir
link_target = File.join "..", ".."
$web_server_links_dir.mkpath
$environments.each do |e|
  link_name = $web_server_links_dir + e
  if File.exist?(link_name)
    if FileTest.symlink?(link_name)
      unless File.readlink(link_name) == link_target
        puts "symlink '#{link_name}' exists, but doesn't appear to link to the correct place"
      end
    else
      puts "couldn't make symlink '#{link_name}', something's already there"
    end
  else
    link_name.symlink_to_target(link_target)
  end
end

def generate_port_from_project_and_env(project_dir, env)
  config = project_dir.project_config_files_contents
  pseudo_random_number = Digest::SHA1.hexdigest(config + env).hex
  $starting_port + (pseudo_random_number % $port_pool_size)
end

def root_link?(path)
  path.basename.to_s == "root"
end

def root_link_target_name_in_symlink_dir(dir)
  if root_link_path = dir.children.detect { |p| root_link? p }
    root_realpath = root_link_path.realpath
    root_app_link_name = dir.children.detect { |p| p.realpath == root_realpath and p != root_link_path }.basename
  end
end

def rewrite_line_and_symlink_lines_from_symlink_dir(dir)
  rewrite_line = if app_link_name = root_link_target_name_in_symlink_dir(dir)
                   "        rewrite ^/$ /#{app_link_name} redirect;"
                 end
  symlink_lines = dir.children.reject { |p| root_link? p }.map do |s|
    "        passenger_base_uri /#{s.basename};\n"
  end
  [rewrite_line, symlink_lines]
end

def generate_conf_file_contents(dir, env)
  port = generate_port_from_project_and_env dir, env
  server_name = server_name_from_project_dir_and_env(dir, env)
  full_path_to_dir = File.expand_path "#{$web_server_links_dir}/#{env}/#{dir.projects_relative_path}"
  root = if dir.project_directory?
           "#{full_path_to_dir}/public"
         else
           "#{full_path_to_dir}"
         end
  rewrite_line, symlink_lines = dir.symlink_directory? ? rewrite_line_and_symlink_lines_from_symlink_dir(dir) : []
  <<-END
    server {
        listen #{port};
        listen #{server_name}:80;
        server_name #{server_name};
        root #{root};
        passenger_enabled on;

#{rewrite_line}
        rails_env #{env};
        rails_spawn_method conservative;
        
#{symlink_lines}
        client_max_body_size 100m;
        client_body_timeout   300;
    }
END
end

def write_conf_file(p, env)
  project_vhost_dir = $web_server_vhost_nginx_dir + p.projects_relative_path
  project_vhost_dir.mkpath
  project_env_vhost_filename = project_vhost_dir + "#{env}.conf"
  new_contents = generate_conf_file_contents(p, env)
  if project_env_vhost_filename.exist?
    old_contents = project_env_vhost_filename.read
    if old_contents != new_contents
      puts "#{project_env_vhost_filename} exists, but doesn't match"
    end
  else
    project_env_vhost_filename.write new_contents
  end
  project_env_vhost_filename.expand_path
end

# generate files for each proj/env
list_of_conf_files = []
(project_dirs + symlink_dirs).each do |p|
  $environment_map[p.realpath].each do |env|
    list_of_conf_files << write_conf_file(p, env)
  end
end

$web_server_vhost_nginx_conf.write(list_of_conf_files.map { |p| "include #{p};\n" })


pp project_dirs if $VERBOSE
pp symlink_dirs if $VERBOSE
pp $environments if $VERBOSE

puts "you'll need to make sure this line is in your nginx config, in the http block:"
puts "  include #{$web_server_vhost_nginx_conf};"
