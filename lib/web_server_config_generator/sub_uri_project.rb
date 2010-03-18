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
      if root_project
        File.basename(root_project.relative_root_url_for_env(env))
      else
        puts "\nWarning: Couldn't find root app in #{self}.  Specify a root app in one of the configuration files if you want to be redirected to that app when visiting '/'"
      end
    end

    def generate_conf_file_contents(options)
      port = self.generate_port_from_env(options[:env])
      full_path_to_dir = File.expand_path "#{@web_config_generator.web_server_sub_uri_apps_dir}/#{projects_relative_project_path}"
      root = full_path_to_dir
      
      NginxConf.new(:port => port, :server_names => [server_name],
                    :root => root, :environment => options[:env],
                    :sub_uri_root_app => root_link_target_name_in_symlink_dir,
                    :base_uri_names => projects.map { |p| File.basename(p.relative_root_url_for_env(env)) }).contents
    end
    
  end
end
