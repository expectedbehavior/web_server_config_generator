require File.dirname(__FILE__) + '/test_helper.rb'

class TestWebServerConfigGenerator < Test::Unit::TestCase

  def setup
    $CONFIG_FILES_DIR = File.join(File.dirname(__FILE__), "test_generated_config_files")
    FileUtils.rm_r $CONFIG_FILES_DIR if File.exist? $CONFIG_FILES_DIR
    
    $CMD = File.join(File.dirname(__FILE__), "..", "bin", "web_server_setup")
    $CMD_STANDARD_OPTIONS = "--no-add-hosts --no-restart-nginx -l #{$CONFIG_FILES_DIR}"
    
    $EXAMPLE_APPS = [
                     $STAND_ALONE_APP = File.join(File.dirname(__FILE__), "test_apps", "stand_alone_app"),
                     $SUB_URI_APP_FOO = File.join(File.dirname(__FILE__), "test_apps", "sub_uri_app_foo"),
                     $SUB_URI_APP_BAR = File.join(File.dirname(__FILE__), "test_apps", "sub_uri_app_bar"),
                    ]
  end
  
  def test_help
    cmd = "#{$CMD} -h"
    assert_match /Usage/, `#{cmd}`
  end
  
  def test_specifying_config_location
    loc = $CONFIG_FILES_DIR
    assert !File.exist?(loc)
    cmd = "#{$CMD} --no-add-hosts --no-restart-nginx -l #{loc} #{$STAND_ALONE_APP}"
    `#{cmd}`
    assert File.exist?(loc), "config file dir wasn't created"
    assert File.exist?(File.join(loc, "links")), "config file links dir wasn't created"
    assert File.exist?(File.join(loc, "vhost")), "config file vhost dir wasn't created"
  end
  
  def test_supplying_specific_env
    cmd = "#{$CMD} #{$CMD_STANDARD_OPTIONS} -e development #{$STAND_ALONE_APP}"
    `#{cmd}`
    config_files_paths = Dir[File.join($CONFIG_FILES_DIR, "vhost", "**", "*.conf")]
    uniq_config_file_names = config_files_paths.map { |p| File.basename(p) }.uniq
    env_conf_file_names = uniq_config_file_names - ["projects.conf"]
    assert env_conf_file_names == ["development.conf"], "expected only development.conf, found: #{env_conf_file_names.inspect}"
  end
end
