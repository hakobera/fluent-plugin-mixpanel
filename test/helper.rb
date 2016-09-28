require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'test/unit'
require 'webmock/test_unit'
WebMock.disable_net_connect!(:allow_localhost => true)

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'fluent/test'
unless ENV.has_key?('VERBOSE')
  nulllogger = Object.new
  nulllogger.instance_eval {|obj|
    def method_missing(method, *args)
      # pass
    end
  }
  $log = nulllogger
end

def unused_port
  s = TCPServer.open(0)
  port = s.addr[1]
  s.close
  port
end

require 'fluent/plugin/mixpanel_ruby_error_handler'
require 'fluent/plugin/out_mixpanel'
require 'fluent/plugin/in_http_mixpanel'

class Test::Unit::TestCase
end
