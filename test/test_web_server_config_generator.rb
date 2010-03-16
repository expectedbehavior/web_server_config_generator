require File.dirname(__FILE__) + '/test_helper.rb'
require 'yaml'

class TestWebServerConfigGenerator < Test::Unit::TestCase

  def setup
    $EXAMPLE_APPS_DIR = File.join(File.dirname(__FILE__), "test_apps")
    $EXAMPLE_APPS = [
                     $WEBCONFIG_APPS = [
                                        $STAND_ALONE_APP = File.join($EXAMPLE_APPS_DIR, "stand_alone_app"),
                                        $SUB_URI_APP_FOO = File.join($EXAMPLE_APPS_DIR, "sub_uri_app_foo"),
                                        $SUB_URI_APP_BAR = File.join($EXAMPLE_APPS_DIR, "sub_uri_app_bar"),
                                        ],
                     $SUB_URI_APP = File.join($EXAMPLE_APPS_DIR, "sub_uri_apps"),
                     $NO_WEBCONFIG_APP = File.join($EXAMPLE_APPS_DIR, "no_webconfig_app"),
                    ].flatten

    $NO_WEBCONFIG_APP_WEBCONFIG_PATH = File.join($NO_WEBCONFIG_APP, ".webconfig.yml")
    FileUtils.rm $NO_WEBCONFIG_APP_WEBCONFIG_PATH if File.exist? $NO_WEBCONFIG_APP_WEBCONFIG_PATH

    $CONFIG_FILES_DIR = File.join($EXAMPLE_APPS_DIR, "web_server_files")
    FileUtils.rm_r $CONFIG_FILES_DIR if File.exist? $CONFIG_FILES_DIR

    $CMD = File.join(File.dirname(__FILE__), "..", "bin", "web_server_setup")
    $CMD_NO_PROMPT_OPTIONS = "--no-add-hosts --no-restart-nginx -p #{$EXAMPLE_APPS_DIR}"
    $CMD_STANDARD_OPTIONS = "#{$CMD_NO_PROMPT_OPTIONS} -l #{$CONFIG_FILES_DIR} -p #{$EXAMPLE_APPS_DIR}"
  end
  
  def test_only_generate_configs_for_projects_with_webconfig_yml
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS}"
    `#{cmd}`
    $WEBCONFIG_APPS.each do |app|
      config_files_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", File.basename(app), "*.conf")]
      assert config_files_paths.any?, "couldn't find any conf files for app #{File.basename(app)}"
    end

    config_files_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", File.basename($SUB_URI_APP), "*.conf")]
    assert config_files_paths.any?, "couldn't find any conf files for app #{File.basename($SUB_URI_APP)}"

    config_files_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", File.basename($NO_WEBCONFIG_APP), "*.conf")]
    assert config_files_paths.empty?, "found conf files for app #{File.basename($NO_WEBCONFIG_APP)} when I shouldn't have"
  end
  
  def test_generate_webconfig_yml_for_project
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS} #{$NO_WEBCONFIG_APP}"
    `#{cmd}`
    
    expected_config = {
      :test => {:server_name => "no-webconfig-app-test.local", :port => 44971},
      :production => {:server_name => "no-webconfig-app-production.local", :port => 49339},
      :development => {:server_name => "no-webconfig-app-development.local", :port => 44506}
    }
    assert_equal expected_config, YAML.load_file($NO_WEBCONFIG_APP_WEBCONFIG_PATH)
  end
  
  def test_config_dir_creation_when_specifying_projects_dir
    config_dir = $CONFIG_FILES_DIR # File.join($EXAMPLE_APPS_DIR, "web_server_files")
    FileUtils.rm_r config_dir if File.exist? config_dir
    assert !File.exist?(config_dir), "config dir exists and shouldn't yet: #{config_dir}"
    
    cmd = "#{$CMD} #{$CMD_NO_PROMPT_OPTIONS} -l #{config_dir}"
    `#{cmd}`
    
    assert File.exist?(config_dir), "config dir doesn't exist: #{config_dir}"
    FileUtils.rm_r config_dir if File.exist? config_dir
  end
  
  def test_listing_hosts_for_one_app
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS} -n #{$STAND_ALONE_APP}"
    hosts = `#{cmd}`
    assert_equal <<HOSTS, hosts
stand-alone-app-development.local
stand-alone-app-production.local
stand-alone-app-test.local
HOSTS
  end
  
  def test_listing_hosts_for_all_apps
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS} -n"
    hosts = `#{cmd}`
    assert_equal <<HOSTS, hosts
sub-uri-apps-development.local
sub-uri-apps-production.local
sub-uri-apps-test.local
stand-alone-app-development.local
stand-alone-app-production.local
stand-alone-app-test.local
sub-uri-app-foo-development.local
sub-uri-app-foo-production.local
sub-uri-app-foo-test.local
sub-uri-app-bar-development.local
sub-uri-app-bar-production.local
sub-uri-app-bar-test.local
HOSTS
  end
  
  def test_help
    cmd = "#{$CMD} -h"
    assert_match /Usage/, `#{cmd}`
  end
  
  def test_specifying_config_location
    loc = $CONFIG_FILES_DIR
    assert !File.exist?(loc)
    cmd = "#{$CMD} --no-add-hosts --no-restart-nginx -l #{loc} -p #{$EXAMPLE_APPS_DIR}"
    `#{cmd}`
    assert File.exist?(loc), "config file dir wasn't created"
    assert File.exist?(File.join(loc, "links")), "config file links dir wasn't created"
    assert File.exist?(File.join(loc, "vhost")), "config file vhost dir wasn't created"
  end
  
  def test_supplying_specific_env
    # -n so no conf files get created
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS} -n"
    `#{cmd}`
    
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS} -e development"
    `#{cmd}`
    config_files_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", File.basename($STAND_ALONE_APP), "development.conf")]
    uniq_config_file_names = config_files_paths.map { |p| File.basename(p) }.uniq
    env_conf_file_names = uniq_config_file_names - ["projects.conf"]
    assert env_conf_file_names == ["development.conf"], "expected only development.conf, found: #{env_conf_file_names.inspect}"
  end
  
  def test_generate_sub_uri_conf
    # -n so no conf files get created
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS} -n"
    `#{cmd}`
    
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS}"
    `#{cmd}`
    config_file_path = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", File.basename($SUB_URI_APP), "development.conf")].first
    assert_equal <<CONF, File.read(config_file_path)
    server {
        listen 41439;
        listen sub-uri-apps-development.local:80;
        server_name sub-uri-apps-development.local *.sub-uri-apps-development.local;
        root #{File.dirname(File.expand_path(__FILE__))}/test_apps/web_server_files/links/development/sub_uri_apps;
        passenger_enabled on;

        rewrite ^/$ /sub_uri_app_foo redirect;
        rails_env development;
        rails_spawn_method conservative;
        
        passenger_base_uri /sub_uri_app_bar;
        passenger_base_uri /sub_uri_app_foo;

        client_max_body_size 100m;
        client_body_timeout   300;
    }
CONF
  end
end
