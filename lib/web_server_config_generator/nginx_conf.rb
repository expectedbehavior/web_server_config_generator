module WebServerConfigGenerator
  class NginxConf
    def initialize(options)
      @options = options
      raise ArgumentError.new("Must supply port, server_names, root, and environment") unless
        options[:port] && options[:server_names] && options[:root] && options[:environment]
    end
    
    def rewrite_line
      @options[:sub_uri_root_app] && "        rewrite ^/$ /#{@options[:sub_uri_root_app]} redirect;"
    end
    
    def base_uri_lines
      @options[:base_uri_names] && @options[:base_uri_names].map { |n| "        passenger_base_uri /#{n};\n" }.join
    end
    
    def contents
      server_names = @options[:server_names].map { |h| "#{h} *.#{h}" }.join(" ")
      <<-END
    server {
        listen #{@options[:port]};
        listen 80;
        server_name #{server_names};
        root #{@options[:root]};
        passenger_enabled on;

#{rewrite_line}
        rails_env #{@options[:environment]};
        rails_spawn_method conservative;
        
#{base_uri_lines}
        client_max_body_size 100m;
        client_body_timeout   300;
    }
END
    end
  end
end
