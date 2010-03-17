require File.dirname(__FILE__) + '/test_helper.rb'
require 'yaml'
require 'pathname'

at_exit do
  FileUtils.rm "tmp/coverage.data" if File.exist? "tmp/coverage.data"
end

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
    $CMD = "rcov --aggregate tmp/coverage.data --exclude 'rcov,ghost' #{$CMD} --"
    $CMD_NO_PROMPT_OPTIONS = "--no-add-hosts --no-restart-nginx -p #{$EXAMPLE_APPS_DIR}"
    $CMD_STANDARD_OPTIONS = "#{$CMD_NO_PROMPT_OPTIONS} -l #{$CONFIG_FILES_DIR} -p #{$EXAMPLE_APPS_DIR}"
  end
  
  def test_conf_contents_has_been_changed_so_warning_is_generated_for_regular_app
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS}"
    `#{cmd}`
    conf_path = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", File.basename($STAND_ALONE_APP), "*.conf")].first
    contents = File.read conf_path
    File.open(conf_path, "w") { |f| f.write "foo\n#{contents}" }
    assert_match /#{File.basename($STAND_ALONE_APP)}.*#{File.basename(conf_path)}.*exists, but doesn\'t match/, `#{cmd}`
  end
  
  def test_conf_contents_has_been_changed_so_warning_is_generated_for_sub_uri_app
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS}"
    `#{cmd}`
    conf_path = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", "sub-uri-apps-development.local", "*.conf")].first
    contents = File.read conf_path
    File.open(conf_path, "w") { |f| f.write "foo\n#{contents}" }
    assert_match /sub-uri-apps-development.local.*#{File.basename(conf_path)}.*exists, but doesn\'t match/, `#{cmd}`
  end
  
  def test_sub_uri_without_root_specified_generates_warning
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS}"
    assert_match /Specify a symlink named 'root' that points/, `#{cmd}`
  end
  
  def test_ghost_manipulation
    # stub ghost interaction so we don't need to sudo
    # mocking's a hassle while that code is in bin, this'll wait until it's broken out
  end
  
  def test_first_run_prompt_for_projects_dir
    cmd = "#{$CMD} --no-add-hosts --no-restart-nginx -l #{$CONFIG_FILES_DIR} #{$EXAMPLE_APPS_DIR}"
    output = ""
    IO.popen(cmd, "r+") do |f|
      f.puts "y"
      f.close_write
      output << f.read
    end
    
    expect_prompt = "setup #{File.expand_path($EXAMPLE_APPS_DIR)} as your projects dir"
    assert_match /#{Regexp.escape(expect_prompt)}/, output
      
    expect_global_config = {:projects_dirs => [File.expand_path($EXAMPLE_APPS_DIR)]}
    assert_equal expect_global_config, YAML.load_file(File.join($CONFIG_FILES_DIR, "global_config.yml"))
  end
  
  def test_sub_uri_conf_references_generated_links_dir
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS}"
    `#{cmd}`
    conf_path = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", "sub-uri-apps-development.local", "*.conf")].first
    root_path = File.read(conf_path).grep(/root/).first.sub(/.*root (.*);/, '\1').strip
    assert_equal Pathname.new(File.join($CONFIG_FILES_DIR, "sub_uri_apps", "sub-uri-apps-development.local")).realpath,
                   Pathname.new(root_path).realpath
  end
  
  def test_sub_uri_apps_generate_link_dir
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS}"
    `#{cmd}`
    conf_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", "sub-uri-apps-development.local", "*.conf")]
    assert_equal 1, conf_paths.size, "should have found 1 conf file for sub_uri app"
    link_paths = Dir[File.join($CONFIG_FILES_DIR, "sub_uri_apps", "sub-uri-apps-development.local", "*")]
    assert_equal 3, link_paths.size, "should have found 3 links for sub_uri apps, 2 apps, 1 root"
    assert link_paths.all? { |l| File.symlink? l }, "expected all symlinks, but found other stuff in sub uri links dir"
    assert link_paths.detect { |l| File.basename(l) == "root" }, "expected a root link, but couldn't find one"
  end
  
  def test_only_generate_conf_for_specific_project
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS} #{$STAND_ALONE_APP}"
    `#{cmd}`
    ($WEBCONFIG_APPS - [$STAND_ALONE_APP]).each do |app|
      config_files_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", File.basename(app), "*.conf")]
      assert config_files_paths.empty?, "found conf files for app #{File.basename(app)} when I shouldn't have"
    end

    config_files_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", File.basename($SUB_URI_APP), "*.conf")]
    assert config_files_paths.empty?, "found conf files for app #{File.basename($SUB_URI_APP)} when I shouldn't have"

    config_files_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", File.basename($NO_WEBCONFIG_APP), "*.conf")]
    assert config_files_paths.empty?, "found conf files for app #{File.basename($NO_WEBCONFIG_APP)} when I shouldn't have"

    config_files_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", File.basename($STAND_ALONE_APP), "*.conf")]
    assert config_files_paths.any?, "couldn't find any conf files for app #{File.basename($STAND_ALONE_APP)}"
  end
  
  def test_only_generate_configs_for_projects_with_webconfig_yml_and_generate_for_correct_envs
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS}"
    `#{cmd}`
    $WEBCONFIG_APPS.each do |app|
      config_files_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", File.basename(app), "*.conf")]
      assert_equal 3, config_files_paths.size, "didn't find correct number of conf files for app #{File.basename(app)}"
    end

    config_files_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", "sub-uri-apps-development.local", "*.conf")]
    assert_equal 1, config_files_paths.size, "couldn't find any conf files for app sub-uri-apps-development.local"

    config_files_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", File.basename($NO_WEBCONFIG_APP), "*.conf")]
    assert config_files_paths.empty?, "found conf files for app #{File.basename($NO_WEBCONFIG_APP)} when I shouldn't have"
  end
  
  def test_generate_webconfig_yml_for_project
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS} #{$NO_WEBCONFIG_APP}"
    `#{cmd}`
    
    expected_config = {
      :test => {:server_names => ["no-webconfig-app-test.local"], :port => 44971},
      :production => {:server_names => ["no-webconfig-app-production.local"], :port => 49339},
      :development => {:server_names => ["no-webconfig-app-development.local"], :port => 44506}
    }
    assert_equal expected_config, YAML.load_file($NO_WEBCONFIG_APP_WEBCONFIG_PATH)
    
    config_files_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", "*.conf")]
    config_files_paths.reject! { |p| File.basename(p) == "projects.conf" }
    assert_equal 3, config_files_paths.size, "found more conf files than should have for only 1 app #{$NO_WEBCONFIG_APP}"
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
    assert_equal <<HOSTS.sort, hosts.sort
stand-alone-app-development.local
stand-alone-app-production.local
stand-alone-app-test.local
HOSTS
  end
  
  def test_listing_hosts_for_all_apps
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS} -n"
    hosts = `#{cmd}`
    assert_equal <<HOSTS.sort, hosts.sort
sub-uri-apps-development.local
sub-uri-apps-no-root-development.local
stand-alone-app-development.local
stand-alone-app-production.local
stand-alone-app-test.local
sub-uri-app-foo-development.local
sub-uri-app-foo-production.local
sub-uri-app-foo-test.local
sub-uri-app-foo-no-root-development.local
sub-uri-app-foo-no-root-production.local
sub-uri-app-foo-no-root-test.local
sub-uri-app-bar-development.local
sub-uri-app-bar-production.local
sub-uri-app-bar-test.local
sub-uri-app-bar-no-root-development.local
sub-uri-app-bar-no-root-production.local
sub-uri-app-bar-no-root-test.local
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
    config_file_path = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", "sub-uri-apps-development.local", "development.conf")].first
    assert_equal <<CONF, File.read(config_file_path)
    server {
        listen 48166;
        listen sub-uri-apps-development.local:80;
        server_name sub-uri-apps-development.local *.sub-uri-apps-development.local;
        root #{File.dirname(File.expand_path(__FILE__))}/test_apps/web_server_files/sub_uri_apps/sub-uri-apps-development.local;
        passenger_enabled on;

        rewrite ^/$ /foo redirect;
        rails_env development;
        rails_spawn_method conservative;
        
        passenger_base_uri /bar;
        passenger_base_uri /foo;

        client_max_body_size 100m;
        client_body_timeout   300;
    }
CONF
  end
end
