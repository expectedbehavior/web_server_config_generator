module WebServerConfigGenerator
  class ProjectDirectory < Pathname
    STARTING_PORT = 40_000
    PORT_POOL_SIZE = 10_000
    
    def path
      self
    end
    
    def +(other)
      other = self.class.new(other) unless self.class === other
      self.class.new(plus(@path, other.to_s))
    end
    
#     def file_path_split
#       return [path] if path.parent.expand_path == path.expand_path
#       self.class.new(path.parent.expand_path).file_path_split + [path.basename]
#     end

    def environments
      Dir[path.to_s + "/config/environments/*.rb"].map { |p| File.basename(p).gsub(/\.rb/, '') }
    end
    
#     def without(path)
#       self.to_s.sub(path, '')
#     end
    
    def project_name
      self.basename.to_s.gsub(/[^[:alnum:]]/, '-').squeeze('-').gsub(/(^-|-$)/, '').downcase
    end
    
    def default_webconfig_options
      opts = {}
      environments.each do |env|
        opts[env.to_sym] = {
          :port => self.generate_port_from_env(env),
          :server_names => [self.server_name_from_env(env)],
        }
      end
      opts
    end
    
    def project_webconfig
      @project_webconfig ||=
        begin
          config = default_webconfig_options.merge(File.exist?(self.project_webconfig_path) ?
                                                     YAML.load_file(self.project_webconfig_path) :
                                                     {})
          
          unless File.exist?(self.project_webconfig_path)
            save_project_webconfig config
          end
          
          project_webconfig_proc(config)
        end
    end
    
    def save_project_webconfig(config)
      File.open(project_webconfig_path, "w") { |f| f.write config.to_yaml }
    end
    
    def project_webconfig_proc(config)
      lambda do |env|
        # lets us have top level defaults in the config, and merge those under env specific options
        config.dup.merge(config[env] || {})
      end
    end
    
    def project_webconfig_path
      File.join(self, ".webconfig.yml")
    end

    def project_config_files_contents
      config_contents = ""
      config_dir = File.join(self, "config")
      Find.find(config_dir) do |path|
        config_contents << File.open(path) { |f| f.read } if File.file? path
      end
      config_contents
    end

    def generate_port_from_env(env)
      config = self.project_config_files_contents
      pseudo_random_number = Digest::SHA1.hexdigest(config + env.to_s).hex
      STARTING_PORT + (pseudo_random_number % PORT_POOL_SIZE)
    end

    def server_name_from_env(env)
      "#{self.project_name}-#{env}.local"
    end
    
    def projects_relative_project_path
      File.expand_path(self).sub(File.expand_path(WebServerSetup::Directory.projects_dir), '')
    end
    
    def server_name_env_pairs
      pairs = []
      environments.each do |env|
        env = env.to_sym
        project_webconfig[env][:server_names].each do |h|
          pairs << [h, env]
        end
      end
      pairs
    end
    
    def relative_root_url_for_env(env)
      project_webconfig[env.to_sym][:relative_root_url]
    end
    
    def relative_root_url_root_for_env(env)
      project_webconfig[env.to_sym][:relative_root_url_root]
    end

    def generate_conf_file_contents(options)
      env = options[:env].to_sym
      port = project_webconfig[env][:port]
      server_name_listen_lines = project_webconfig[env][:server_names].map { |h| "        #{h}:80;" }.join("\n")
      server_names = project_webconfig[env][:server_names].map { |h| "#{h} *.#{h}" }.join(" ")
      full_path_to_dir = File.expand_path "#{options[:web_server_links_dir]}/#{env}/#{projects_relative_project_path}"
      root = "#{full_path_to_dir}/public"
      <<-END
    server {
        listen #{port};
#{server_name_listen_lines}
        server_name #{server_names};
        root #{root};
        passenger_enabled on;

        rails_env #{env};
        rails_spawn_method conservative;
        
        client_max_body_size 100m;
        client_body_timeout   300;
    }
END
    end
    
  end
end
