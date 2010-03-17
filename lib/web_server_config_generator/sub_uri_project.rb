module WebServerConfigGenerator
  class SubUriProject
    attr_accessor :server_name, :env, :projects
    
    def initialize(server_name, env_and_projects, web_config_generator)
      @server_name = server_name
      @env = env_and_projects[:env]
      @projects = env_and_projects[:projects]
      @web_config_generator = web_config_generator
    end
    
    def to_s
      server_name.dup
    end
    alias :to_str :to_s
    
    def server_name_from_env(env)
      server_name
    end
    
    def server_names
      [server_name]
    end

    def generate_port_from_env(env)
      pseudo_random_number = projects.inject(0) { |sum, p| sum + p.generate_port_from_env(env) }
      WebServerConfigGenerator::STARTING_PORT + (pseudo_random_number % WebServerConfigGenerator::PORT_POOL_SIZE)
    end
    
    def projects_relative_project_path
      server_name
    end
    
    def root_project
      projects.detect { |p| p.relative_root_url_root_for_env(env) }
    end

    def root_link_target_name_in_symlink_dir
      File.basename(root_project.relative_root_url_for_env(env)) if root_project
    end

    def rewrite_line_and_symlink_lines_from_symlink_dir
      @@rewrite_line_and_symlink_lines_from_symlink_dir_cache ||= {}
      @@rewrite_line_and_symlink_lines_from_symlink_dir_cache[self] ||= begin
        rewrite_line = if app_link_name = root_link_target_name_in_symlink_dir
                         "        rewrite ^/$ /#{app_link_name} redirect;"
                       else
                         puts "\nWarning: Couldn't find root link in #{self}.  Specify a symlink named 'root' that points to one of the other symlinks if you want to be redirected to that app when visiting '/'"
                       end
        symlink_lines = projects.map do |p|
          "        passenger_base_uri /#{File.basename(p.relative_root_url_for_env(env))};\n"
        end
        [rewrite_line, symlink_lines]
      end
    end

    def generate_conf_file_contents(options)
      port = self.generate_port_from_env(options[:env])
#       server_name = self.server_name_from_env(options[:env])
      puts "fixme abstracts conf template sub uri project gen"
      full_path_to_dir = File.expand_path "#{@web_config_generator.web_server_sub_uri_apps_dir}/#{projects_relative_project_path}"
      root = full_path_to_dir
      
      rewrite_line, symlink_lines = rewrite_line_and_symlink_lines_from_symlink_dir
      <<-END
    server {
        listen #{port};
        listen 80;
        server_name #{server_name} *.#{server_name};
        root #{root};
        passenger_enabled on;

#{rewrite_line}
        rails_env #{options[:env]};
        rails_spawn_method conservative;
        
#{symlink_lines}
        client_max_body_size 100m;
        client_body_timeout   300;
    }
END
    end
    
  end
end
