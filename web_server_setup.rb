#!/usr/bin/env ruby

require 'fileutils'
require 'pp'
require 'find'
require 'digest/sha1'
require 'pathname'
require 'getoptlong'

opts = GetoptLong.new(*[
                      [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
                      [ '--environment', '-e', GetoptLong::REQUIRED_ARGUMENT ],
                      [ '--hosts', '-n', GetoptLong::NO_ARGUMENT ],
                      [ '--create-web-server-files-dir', '-c', GetoptLong::NO_ARGUMENT ],
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
  else
    puts <<-STR
Usage: #{File.basename(__FILE__)} [project(s) dir] [OPTION]

This will generate web server configuration files for your projects.

If you supply a project directory we assume you have run this before and will just generate the files for that project.  If you specify your projects directory we will generate the files for all projects found.  Not supplying a directory is the same as supplying your current directory.

No flags = try to generate files for all envs

  -e <env> specify a specific environemnt to generate
  -c       create web_server_files directory (useful the first time you run this script)

  -h \t this help screen

    STR
    exit 0
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
    self.without($projects_dir)
  end

  def project_config_files_contents
    config_contents = ""
    config_dir = File.join(self, "config")
    Find.find(config_dir) do |path|
      config_contents << File.open(path) { |f| f.read } if File.file? path
    end
    config_contents
  end
end

$web_server_files_dir_name = "web_server_files"

project_or_projects_dir = ProjectDirectory.new(ARGV.first ? File.expand_path(ARGV.first) : FileUtils.pwd)
if $CREATE_WEB_SERVER_FILES_DIR
  $projects_dir = project_or_projects_dir
else
  unless $projects_dir = project_or_projects_dir.find_projects_dir
    puts "couldn't find projects dir from project dir, make sure #{$web_server_files_dir_name} exists"
    exit 1
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
  $environment_map = project_dirs.inject({}) { |m, o| m[o.basename.to_s] = o.environments; m }
  symlink_env_map = symlink_dirs.inject({}) do |m, symlink_dir|
    envs = symlink_dir.children.map { |p| p.realpath.parent.environments }.flatten.uniq
    m[symlink_dir.basename.to_s] = $ENVS.any? ? $ENVS : envs.uniq
    m
  end
  $environment_map.merge! symlink_env_map
end
$environments = $environment_map.values.flatten.uniq

def server_name_from_project_dir_and_env(dir, env)
  "#{File.basename(dir)}_#{env}.local"
end

if $PRINT_HOSTS
  $environment_map.each do |dir, envs|
    envs.each do |env|
      puts server_name_from_project_dir_and_env(dir, env)
    end
  end
  exit 0
end

# setup web_server_links_dir
link_target = File.join "..", ".."
FileUtils.mkdir_p $web_server_links_dir
$environments.each do |e|
  link_name = File.join($web_server_links_dir, e)
  if File.exist?(link_name)
    if FileTest.symlink?(link_name)
      unless File.readlink(link_name) == link_target
        puts "symlink '#{link_name}' exists, but doesn't appear to link to the correct place"
      end
    else
      puts "couldn't make symlink '#{link_name}', something's already there"
    end
  else
    File.symlink link_target, link_name
  end
end

def generate_port_from_project_and_env(project_dir, env)
  config = project_dir.project_config_files_contents
  pseudo_random_number = Digest::SHA1.hexdigest(config + env).hex
  $starting_port + (pseudo_random_number % $port_pool_size)
end

def rewrite_line_and_symlink_lines_from_symlink_dir(dir)
  symlink_names = dir.directory_contents(dir, false).map { |p| p.basename.to_s }
  root_link = symlink_names.delete("root")
  rewrite_line = if root_link
                   root_realpath = ProjectDirectory.new(File.join(dir, root_link)).realpath
                   root_app_link = symlink_names.detect { |s| ProjectDirectory.new(File.join(dir, s)).realpath == root_realpath }
                   "        rewrite ^/$ /#{root_app_link} redirect;"
                 end
  symlink_lines = symlink_names.map { |s| "        passenger_base_uri /#{s};\n" }
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

# generate files for each proj/env
list_of_conf_files = []
(project_dirs + symlink_dirs).each do |p|
  project_vhost_dir = File.join($web_server_vhost_nginx_dir, p.basename)
  FileUtils.mkdir_p project_vhost_dir
  $environment_map[p.basename.to_s].each do |env|
    project_env_vhost_filename = File.join(project_vhost_dir, "#{env}.conf")
    list_of_conf_files << File.expand_path(project_env_vhost_filename)
    new_contents = generate_conf_file_contents(p, env)
    if File.exist? project_env_vhost_filename
      old_contents = File.open(project_env_vhost_filename) { |f| f.read }
      if old_contents != new_contents
        puts "#{project_env_vhost_filename} exists, but doesn't match"
      end
    else
      File.open(project_env_vhost_filename, "w") { |f| f.write new_contents }
    end
  end
end

File.open($web_server_vhost_nginx_conf, "w") do |f|
  f.write list_of_conf_files.map { |p| "include #{p};\n" }
end


pp project_dirs
pp symlink_dirs
pp $environments

puts "you'll need to make sure this line is in your nginx config, in the http block:"
puts "  include #{$web_server_vhost_nginx_conf};"
