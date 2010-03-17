$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

module WebServerConfigGenerator
  VERSION = '0.0.1'
  STARTING_PORT = 40_000
  PORT_POOL_SIZE = 10_000
end
