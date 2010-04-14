module WebServerConfigGenerator
  class Generator
    def initialize(options)
      options.each do |opt, val|
        instance_variable_set("@#{opt}", val)
      end
      
      @starting_port = options[:starting_port] || 40000
      @port_pool_size = options[:port_pool_size] || 10000
      
      @environment_map = Hash.new(options[:environments]) if options[:environments]

      setup_config_dir
      
      @project_or_projects_dir ||= projects_dir
    end
    
    def write_conf_files
      FileUtils.cd projects_dir do
        # generate files for each proj/env
        list_of_conf_files = []
        app_projects.each do |p|
          environment_map[p].each do |env|
            list_of_conf_files << write_conf_file(p, env)
          end
        end
        
        sub_uri_projects.each do |p|
          create_sub_uri_links_dir p
          list_of_conf_files << write_conf_file(p, p.env)
        end

        current_lines = []
        web_server_vhost_nginx_conf.read.each_line { |l| current_lines << l }
        new_lines = current_lines + list_of_conf_files.map { |p| "include #{p};\n" }
        new_lines.uniq!
        new_lines.sort!
        web_server_vhost_nginx_conf.write(new_lines.join)
      end
    end
    
    def create_sub_uri_links_dir(sub_uri_project)
      env = sub_uri_project.env
      
      web_server_sub_uri_apps_dir.mkdir unless web_server_sub_uri_apps_dir.exist?
      links_dir = web_server_sub_uri_apps_dir + sub_uri_project.server_name
      links_dir.mkdir unless links_dir.exist?
      sub_uri_project.projects.each do |p|
        symlink p.expand_path + "public", File.join(links_dir, p.relative_root_url_for_env(env))
        if p.relative_root_url_root_for_env(env)
          symlink p.expand_path + "public", File.join(links_dir, "root")
        end
      end
    end

    def server_names
      projects.map { |p| p.server_names }.flatten.uniq
    end
    
    def delete_ghost_entries
      global_config[:hosts].each do |host|
        Host.delete host
      end
      global_config[:hosts] = []
      save_global_config(global_config)
    end
    
    def add_ghost_entries
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
          if $TEST_MODE
            puts "would have added #{server_name} -> 127.0.0.1"
          else
            added << Host.add(server_name)
            global_config[:hosts] ||= []
            global_config[:hosts] << server_name
            save_global_config(global_config)
          end
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
    
    def setup_config_dir
      unless File.exist?(config_dir)
        unless dir = $PROJECTS_DIRECTORY
          puts "It looks like this is the first time you've run me."
          puts 
          dir = @project_or_projects_dir || FileUtils.pwd
          unless agree("setup #{dir} as your projects dir? [Y/n]") { |q| q.default = "Y"}
            puts "for your first run you'll need to supply your projects directory"
            exit
          end
          puts "setting up config dir"
        end
        
        FileUtils.mkdir_p config_dir
        initial_config = { :projects_dirs => [File.expand_path(dir)]}
        save_global_config(initial_config)
      end
    end
    
    def symlink(link_target, link_name)
      if File.exist?(link_name)
        if FileTest.symlink?(link_name)
          unless Pathname.new(link_name).realpath == Pathname.new(link_target).realpath
            puts "symlink '#{link_name}' exists, but doesn't appear to link to the correct place"
          end
        else
          puts "couldn't make symlink '#{link_name}', something's already there"
        end
      else
        File.symlink link_target, link_name
      end
    end
    
    def setup_webserver_links_dir
      web_server_links_dir.mkpath
      environments.each do |e|
        link_name = web_server_links_dir + e
        symlink(projects_dir, link_name)
      end
    end
    
    def app_projects
      @app_projects ||=
        begin
          find_project_and_symlink_dirs
          @app_projects
        end
    end
    
    def sub_uri_projects
      return @sub_uri_projects if @sub_uri_projects
      server_name_env_project_map = {}
      app_projects.each do |p|
        p.server_name_env_pairs.each do |server_name, env|
          server_name_env_project_map[server_name] ||= {}
          server_name_env_project_map[server_name][:env] ||= env
          raise "can't have one hostname map to multiple envs" if server_name_env_project_map[server_name][:env] != env
          server_name_env_project_map[server_name][:projects] ||= []
          server_name_env_project_map[server_name][:projects] << p
        end
      end
      server_name_env_project_map = server_name_env_project_map.select do |server_name, env_and_projects|
        # more than one project with the same server_name
        # don't count projects that evaluate to the same path
        env_and_projects[:projects].map { |p| p.realpath }.uniq.size > 1
      end
      @sub_uri_projects = server_name_env_project_map.map do |server_name, env_and_projects|
        WebServerConfigGenerator::SubUriProject.new(server_name, env_and_projects, self)
      end
    end
    
    def projects
      app_projects + sub_uri_projects
    end
    
    def environments
      @environments ||= environment_map.values.flatten.uniq
    end
    
    def web_server_vhost_nginx_conf
      web_server_vhost_nginx_dir + "projects.conf"
    end
    
    def check_nginx_conf
      unless nginx_conf =~ /include.*#{web_server_vhost_nginx_conf}/
        puts "\nWarning: You'll need to make sure this line is in your nginx config, in the http block:"
        puts "  include #{web_server_vhost_nginx_conf};"
      end

      unless nginx_conf =~ /server_names_hash_bucket_size.*128/
        puts "\nWarning: Couldn't find the following line in your nginx conf.  It should be in the http block."
        puts "  server_names_hash_bucket_size 128;"
      end
    end
    
    def prompt_to_restart_nginx
      puts
      if $RESTART_NGINX || ($RESTART_NGINX.nil? && agree("Restart nginx? [Y/n]") { |q| q.default = "Y"})
        puts "Restarting nginx..."
        cmd = "sudo #{nginx} -s quit; sleep 1 && sudo #{nginx}"
        puts "running: #{cmd}"
        system cmd
      end
    end
    
    def web_server_links_dir
      config_dir + "links"
    end
    
    def projects_dir
      WebServerConfigGenerator::Pathname.new(global_config[:projects_dirs].first).expand_path
    end
    
    def web_server_sub_uri_apps_dir
      config_dir + "sub_uri_apps"
    end
    
    private
    
    def config_dir
      @config_dir ||=
        begin
          WebServerConfigGenerator::Pathname.new $WEB_SERVER_FILES_DIR || begin
                                     raise "Couldn't fine $HOME" unless home_dir = ENV["HOME"]
                                     File.join(home_dir, ".webconfig")
                                   end
        end
    end
    
    def global_config(reload = false)
      @global_config = nil if reload
      @global_config ||= YAML.load_file(global_config_path)
    end
    
    def save_global_config(config)
      @global_config = config
      File.open(global_config_path, "w") { |f| f.write config.to_yaml }
    end
    
    def global_config_path
      File.join(config_dir, "global_config.yml")
    end
    
    def web_server_vhost_dir
      config_dir + "vhost"
    end
    
    def web_server_vhost_nginx_dir
      web_server_vhost_dir + "nginx"
    end
    
    def find_project_and_symlink_dirs
      @app_projects ||= []

      if @project_or_projects_dir.expand_path != projects_dir.expand_path
        @app_projects = [WebServerConfigGenerator::ProjectDirectory.new(@project_or_projects_dir, self)]
        return
      end
      
      [
       Dir[File.join(projects_dir, "*", ".webconfig.yml")],
       Dir[File.join(projects_dir, "*", "*", ".webconfig.yml")],
       Dir[File.join(projects_dir, "*", "*", "*", ".webconfig.yml")],
      ].flatten.map { |p| Pathname.new(p).realpath.dirname }.uniq.each do |path|
        @app_projects << WebServerConfigGenerator::ProjectDirectory.new(path, self)
      end
    end
    
    def projects_environment_map
      app_projects.inject({}) { |map, p| map[p] = p.environments; map }
    end
    
    def symlinks_environment_map
      sub_uri_projects.inject({}) { |map, p| map[p] = p.env.to_s; map }
    end
    
    def environment_map
      @environment_map ||= projects_environment_map.merge(symlinks_environment_map)
    end

    def projects_relative_project_path(dir)
      File.expand_path(dir).sub(File.expand_path(projects_dir), '').sub(/^\//, '')
    end

    def write_conf_file(p, env)
      project_vhost_dir = web_server_vhost_nginx_dir + projects_relative_project_path(p)
      project_vhost_dir.mkpath
      project_env_vhost_filename = project_vhost_dir + "#{env}.conf"
      new_contents = p.generate_conf_file_contents(:env => env)
#       if project_env_vhost_filename.exist?
#         old_contents = project_env_vhost_filename.read
#         if old_contents != new_contents
#           puts "#{project_env_vhost_filename} exists, but doesn't match"
#         end
#       else
        project_env_vhost_filename.write new_contents
#       end
      project_env_vhost_filename.expand_path
    end
    
    def nginx_conf_path
      m = `#{nginx} -t 2>&1`.match /the configuration file (.*) syntax is ok/
      m[1]
    end
    
    def nginx_conf
      @nginx_conf ||= begin
                        File.read(nginx_conf_path)
                      rescue Exception => e
                        puts "Warning: Couldn't find/read nginx conf"
                        ""
                      end
    end

    def nginx
      nginx_path_options = [
                            "nginx",
                            "/opt/nginx/sbin/nginx"
                           ]
      nginx_path_options.detect { |p| system "which #{p} &> /dev/null" }
    end
    
  end
end