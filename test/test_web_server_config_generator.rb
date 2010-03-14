require File.dirname(__FILE__) + '/test_helper.rb'

class TestWebServerConfigGenerator < Test::Unit::TestCase

  def setup
    $CMD = File.join(File.dirname(__FILE__), "..", "bin", "web_server_setup")
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
    loc = File.join(File.dirname(__FILE__), "test_generated_config_files")
    FileUtils.rm_r loc if File.exist? loc
    assert !File.exist?(loc)
    cmd = "#{$CMD} --no-add-hosts --no-restart-nginx -l #{loc} #{$STAND_ALONE_APP}"
    `#{cmd}`
    assert File.exist?(loc)
    assert File.exist?(File.join(loc, "links"))
    assert File.exist?(File.join(loc, "vhost"))
  end
end
