#!/usr/bin/env ruby

require 'fileutils'
require 'pp'

$projects_dir = File.dirname(File.dirname(File.expand_path(__FILE__)))

$web_server_files_dir = File.join($projects_dir, "web_server_files")
$web_server_links_dir = File.join($web_server_files_dir, "links")
$web_server_vhost_dir = File.join($web_server_files_dir, "vhost")
$web_server_vhost_nginx_dir = File.join($web_server_vhost_dir, "nginx")

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
environments = project_dirs.map { |p| find_environments_in_project(p) }.flatten.uniq

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

def generate_port_from_project_and_env(project_dir, env)
  84
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
project_dirs.each do |p|
  project_vhost_dir = File.join($web_server_vhost_nginx_dir, p)
  FileUtils.mkdir_p project_vhost_dir
  environments.each do |env|
    project_env_vhost_filename = File.join(project_vhost_dir, "#{env}.conf")
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

pp project_dirs
pp symlink_dirs
pp environments
