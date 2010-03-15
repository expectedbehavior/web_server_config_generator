module WebServerConfigGenerator
  class SymlinkDirectory < Pathname
    STARTING_PORT = 40_000
    PORT_POOL_SIZE = 10_000
    
    def path
      self
    end
    
    def +(other)
      other = self.class.new(other) unless self.class === other
      self.class.new(plus(@path, other.to_s))
    end
    
    def project_name
      self.basename.to_s.gsub(/[^[:alnum:]]/, '-').squeeze('-').gsub(/(^-|-$)/, '').downcase
    end

    def environments
      projects.map { |p| p.environments }.flatten.uniq
    end
    
    def projects
      self.children(true).map { |p| ProjectDirectory.new(p.realpath.dirname) }
    end

    def generate_port_from_env(env)
      pseudo_random_number = projects.inject(0) { |sum, p| sum + p.generate_port_from_env(env) }
      STARTING_PORT + (pseudo_random_number % PORT_POOL_SIZE)
    end

    def server_name_from_env(env)
      "#{self.project_name}-#{env}.local"
    end
    
    def projects_relative_project_path
      File.expand_path(self).sub(File.expand_path(WebServerSetup::Directory.projects_dir), '')
    end

    def root_link?(path)
      path.basename.to_s == "root"
    end

    def root_link_target_name_in_symlink_dir
      if root_link_path = self.children.detect { |p| root_link? p }
        root_realpath = root_link_path.realpath
        root_app_link_name = self.children.detect { |p| p.realpath == root_realpath and p != root_link_path }.basename
      end
    end

    def rewrite_line_and_symlink_lines_from_symlink_dir
      @@rewrite_line_and_symlink_lines_from_symlink_dir_cache ||= {}
      @@rewrite_line_and_symlink_lines_from_symlink_dir_cache[self] ||= begin
        rewrite_line = if app_link_name = root_link_target_name_in_symlink_dir
                         "        rewrite ^/$ /#{app_link_name} redirect;"
                       else
                         puts "\nWarning: Couldn't find root link in #{self}.  Specify a symlink named 'root' that points to one of the other symlinks if you want to be redirected to that app when visiting '/'"
                       end
        symlink_lines = self.children.reject { |p| root_link? p }.map do |s|
          "        passenger_base_uri /#{s.basename};\n"
        end
        [rewrite_line, symlink_lines]
      end
    end

    def generate_conf_file_contents(options)
      port = self.generate_port_from_env(options[:env])
      server_name = self.server_name_from_env(options[:env])
      full_path_to_dir = File.expand_path "#{options[:web_server_links_dir]}/#{options[:env]}/#{projects_relative_project_path}"
      root = full_path_to_dir
      
      rewrite_line, symlink_lines = rewrite_line_and_symlink_lines_from_symlink_dir
      <<-END
    server {
        listen #{port};
        listen #{server_name}:80;
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
