#!/usr/bin/env ruby

require 'fileutils'
require 'pp'
require 'find'
require 'digest/sha1'

$projects_dir = File.dirname(File.dirname(File.expand_path(__FILE__)))

$web_server_files_dir = File.join($projects_dir, "web_server_files")
$web_server_links_dir = File.join($web_server_files_dir, "links")
$web_server_vhost_dir = File.join($web_server_files_dir, "vhost")
$web_server_vhost_nginx_dir = File.join($web_server_vhost_dir, "nginx")
$web_server_vhost_nginx_conf = File.join($web_server_vhost_nginx_dir, "projects.conf")

$starting_port = 40000
$port_pool_size = 10000

FileUtils.cd $projects_dir

possible_project_dirs = Dir["*"]
possible_project_dirs -= [File.basename($web_server_files_dir)]
possible_project_dirs = possible_project_dirs.select { |filename| FileTest.directory? filename }

project_dirs = []
symlink_dirs = []

def file_path_split(path)
  return [path] if File.dirname(path) == path
  file_path_split(File.dirname(path)) + [File.basename(path)]
end

def project_directory?(path)
  File.exist? File.join(path, "config", "environment.rb") and
    not FileTest.symlink? path and
    file_path_split(path).size <= 4 # don't want rails apps that are part of tests or whatever
end

def symlink_directory?(path)
  contents = Dir["#{path}/*"]
  contents.any? and contents.all? { |p| FileTest.symlink? p }
end

while possible_project_dir = possible_project_dirs.shift
  if project_directory? possible_project_dir
    project_dirs << possible_project_dir
  elsif symlink_directory? possible_project_dir
    symlink_dirs << possible_project_dir
  elsif FileTest.symlink? possible_project_dir
    # ignore symlinks
  else
    # look in that dir for project directories
    possible_project_dirs += Dir[possible_project_dir + "/*"].select { |filename| FileTest.directory? filename }
  end
end

def find_environments_in_project(path)
  Dir[path + "/config/environments/*.rb"].map { |p| File.basename(p).gsub(/\.rb/, '') }
end

# find all environments
environment_map = project_dirs.inject({}) { |m, o| m[o] = find_environments_in_project(o); m }
environments = environment_map.values.flatten.uniq

# setup web_server_links_dir
link_target = File.join "..", ".."
FileUtils.mkdir_p $web_server_links_dir
environments.each do |e|
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

def project_config_files_contents(project_dir)
  config_contents = ""
  config_dir = File.join(project_dir, "config")
  Find.find(config_dir) do |path|
    config_contents << File.open(path) { |f| f.read } if File.file? path
  end
  config_contents
end

def generate_port_from_project_and_env(project_dir, env)
  config = project_config_files_contents(project_dir)
  pseudo_random_number = Digest::SHA1.hexdigest(config + env).hex
  $starting_port + (pseudo_random_number % $port_pool_size)
end

def generate_conf_file_contents(project_dir, env)
  port = generate_port_from_project_and_env project_dir, env
  server_name = "#{File.basename(project_dir)}_#{env}.local"
  <<-END
    server {
        listen #{port};
        listen #{server_name}:80;
        server_name #{server_name};
        root #{$web_server_links_dir}/#{env}/#{project_dir}/public;
        passenger_enabled on;

        # rewrite ^/$ /splash redirect;
        rails_env #{env};
        rails_spawn_method conservative;
         
        #       passenger_base_uri /splash;
        #       passenger_base_uri /tshirts;
        #       passenger_base_uri /calendar;
        #       passenger_base_uri /projects;
        #       passenger_base_uri /storedb;
        client_max_body_size 100m;
        client_body_timeout   300;
    }
END
end

# generate files for each proj/env
list_of_conf_files = []
project_dirs.each do |p|
  project_vhost_dir = File.join($web_server_vhost_nginx_dir, p)
  FileUtils.mkdir_p project_vhost_dir
  environment_map[p].each do |env|
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
pp environments

puts "you'll need to make sure this line is in your nginx config, in the http block:"
puts "  include #{$web_server_vhost_nginx_conf};"
