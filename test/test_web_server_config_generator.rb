require File.dirname(__FILE__) + '/test_helper.rb'

class TestWebServerConfigGenerator < Test::Unit::TestCase

  def setup
    $CMD = File.join(File.dirname(__FILE__), "..", "bin", "web_server_setup")
  end
  
  def test_help
    cmd = "#{$CMD} -h"
    assert_match /Usage/, `#{cmd}`
  end
end
