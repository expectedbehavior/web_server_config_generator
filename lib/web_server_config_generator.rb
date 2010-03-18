$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

module WebServerConfigGenerator
  VERSION = '0.0.1'
  WEB_SERVER_FILES_DIR_NAME = ".webconfig"
  STARTING_PORT = 40_000
  PORT_POOL_SIZE = 10_000
end

def agree( yes_or_no_question, character = nil )
  ask(yes_or_no_question, lambda { |yn| yn.downcase[0] == ?y}) do |q|
    q.validate                 = /\Ay(?:es)?|no?\Z/i
    q.responses[:not_valid]    = 'Please enter "yes" or "no".'
    q.responses[:ask_on_error] = :question
    q.character                = character
    yield q if block_given?
  end
end
