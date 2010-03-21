module WebServerConfigGenerator
  class ProjectDirectory < Pathname
    EXAMPLE_TEXT = <<-EXAMPLE
# This YAML file describes a hash of the web server configuration for this project.
# here's an example:
#
# --- 
# :test: 
#   :port: 46677
#   :server_names: 
#   - app-test.local
# :development: 
#   :port: 43273
#   :relative_root_url: /foo
#   :relative_root_url_root: true
#   :server_names: 
#   - sub-uri-app-foo-development.local
#   - sub-uri-apps-development.local
# :production: 
#   :port: 46767
#   :server_names: 
#   - app-production.local
#
# Visiting app-test.local will load the app in the test environment.
# Each vost that is configured will listen on all hostnames at the port specified, as well
# as port 80 on all the hostnames specfied.  In the above example accessing
# "http://localhost:46767" will go to the app in production mode, as well as
# "http://app-production.local".
#
# You can also see how to setup relative_root_url apps here in the development section.
# All apps that share a server name and have relative_root_url specified will be setup for relative root access.
# Say, for example, another app had the following config:
#
# --- 
# :development: 
#   :port: 44893
#   :relative_root_url: /bar
#   :server_names: 
#   - sub-uri-app-bar-development.local
#   - sub-uri-apps-development.local
#
# Since these two apps share the server name "sub-uri-apps-development.local" and have relative_root_url
# specified they will be configured so that accessing "http://sub-uri-apps-development.local/foo"
# goes to the first app and accessing "http://sub-uri-apps-development.local/bar" goes to the second.
# In addition, by specifying relative_root_url_root for the foo app you ca visit
# "http://sub-uri-apps-development.local/" and you will access the foo app.


EXAMPLE
    
    attr_reader :original_realpath
    
    def initialize(dir, web_config_generator)
      @web_config_generator = web_config_generator
      super(dir)
      @original_realpath = self.realpath
    end
    
    def path
      self
    end
    
    def realpath
      Pathname.new(self).realpath
    end
    
    def basename
      Pathname.new(self).basename
    end
    
    def expand_path
      Pathname.new(self).expand_path
    end
    
    def eql?(obj)
      return false unless ProjectDirectory === obj
      self.original_realpath == obj.original_realpath
    end
    alias :== :eql?

    def environments
      Dir[path.to_s + "/config/environments/*.rb"].map { |p| File.basename(p).gsub(/\.rb/, '') }
    end
    
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
            add_example_comment_to_config
          end
          
          project_webconfig_proc(config)
        end
    end
    
    def add_example_comment_to_config
      old_contents = File.read(project_webconfig_path)
      new_contents = EXAMPLE_TEXT + old_contents
      File.open(project_webconfig_path, "w") { |f| f.write new_contents }
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
      WebServerConfigGenerator::STARTING_PORT + (pseudo_random_number % WebServerConfigGenerator::PORT_POOL_SIZE)
    end

    def server_name_from_env(env)
      "#{self.project_name}-#{env}.local"
    end
    
    def server_names
      environments.map { |env| project_webconfig[env.to_sym][:server_names] }.flatten
    end
    
    def projects_relative_project_path
      File.expand_path(self).sub(File.expand_path(@web_config_generator.projects_dir), '')
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
    
    def server_names_without_sub_uri_apps_for_env(env)
      project_webconfig[env][:server_names].reject { |n| @web_config_generator.sub_uri_projects.map { |p| p.server_names }.flatten.include? n }
    end

    def generate_conf_file_contents(options)
      env = options[:env].to_sym
      port = project_webconfig[env][:port]
      full_path_to_dir = File.expand_path "#{@web_config_generator.web_server_links_dir}/#{env}/#{projects_relative_project_path}"
      root = "#{full_path_to_dir}/public"
      
      NginxConf.new(:port => port, :server_names => server_names_without_sub_uri_apps_for_env(env),
                    :root => root, :environment => options[:env]).contents
    end
    
  end
end
