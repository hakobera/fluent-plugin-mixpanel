require 'helper'
require 'net/http'
require 'cgi'
require 'base64'
require 'fluent/test'
require 'fluent/test/helpers'
require 'net/http'
require 'serverengine'
require 'fluent/plugin/in_http_mixpanel'

include Fluent::Test::Helpers

class HttpMixpanelInputTest < Test::Unit::TestCase

  class << self
    def startup
      socket_manager_path = ServerEngine::SocketManager::Server.generate_path
      @server = ServerEngine::SocketManager::Server.open(socket_manager_path)
      ENV['SERVERENGINE_SOCKETMANAGER_PATH'] = socket_manager_path.to_s
    end

    def shutdown
      @server.close
    end

    def unused_port
      s = TCPServer.open(0)
      port = s.addr[1]
      s.close
      port
    end
  end

  def setup
    Fluent::Test.setup
  end

  PORT = unused_port
  CONFIG = %[
    port #{PORT}
    bind "127.0.0.1"
    body_size_limit 10m
    keepalive_timeout 5
    respond_with_empty_img true
  ]

  def create_driver(conf=CONFIG)
    Fluent::Test::InputTestDriver.new(Fluent::HttpMixpanelInput).configure(conf, true)
  end

  def test_configure
    d = create_driver
    assert_equal PORT, d.instance.port
    assert_equal '127.0.0.1', d.instance.bind
    assert_equal 10*1024*1024, d.instance.body_size_limit
    assert_equal 5, d.instance.keepalive_timeout
    assert_equal false, d.instance.add_http_headers
  end

  def test_time
    d = create_driver

    time = Time.parse("2011-01-02 13:14:15 UTC").to_i
    Fluent::Engine.now = time

    d.expect_emit "mixpanel.tag1", time, {"a"=>1}
    d.expect_emit "mixpanel.tag2", time, {"a"=>2}

    d.run do
      d.expected_emits.each {|tag, record_time, record|
        res = track("#{tag}", {"json"=>record})
        assert_equal "200", res.code
        assert_equal '1', res.body
        assert_equal 'true', res['access-control-allow-credentials']
        assert_equal 'X-Requested-With', res['access-control-allow-headers']
        assert_equal 'GET, POST, OPTIONS', res['access-control-allow-methods']
        assert_equal 'http://foo.example', res['access-control-allow-origin']
        assert_equal '1728000', res['access-control-max-age']
        assert_equal 'no-cache, no-store', res['cache-control']
      }
    end
  end

  def test_json
    d = create_driver

    time = Time.parse("2011-01-02 13:14:15 UTC").to_i

    d.expect_emit "mixpanel.tag1", time, {"a"=>1}
    d.expect_emit "mixpanel.tag2", time, {"a"=>2}

    d.run do
      d.expected_emits.each {|tag, record_time, record|
        res = track("#{tag}", {"json"=>record, "time"=>record_time.to_s})
        assert_equal "200", res.code
      }
    end

    d.emit_streams.each { |tag, es|
      assert !include_http_header?(es.first[1])
    }
  end

  def test_json_with_add_http_headers
    d = create_driver(CONFIG + "add_http_headers true")

    time = Time.parse("2011-01-02 13:14:15 UTC").to_i

    records = [["mixpanel.tag1", time, {"a"=>1}], ["mixpanel.tag2", time, {"a"=>2}]]

    d.run do
      records.each {|tag, record_time, record|
        res = track("#{tag}", {"json"=>record, "time"=>record_time.to_s})
        assert_equal "200", res.code
      }
    end

    d.emit_streams.each { |tag, es|
      assert include_http_header?(es.first[1])
    }
  end

  def track(tag, params)
    event = tag.sub(/^mixpanel\.(.+)$/, '\1')
    # DO NOT modify the original json; doing so changes what is expected to be emitted
    # and causes the tests to fail
    json = params['json'].dup
    json['time'] = params['time'] if params['time']
    data = {
      event: event,
      properties: json
    }
    data = CGI.escape(Base64.encode64(data.to_json))
    query = "data=#{data}"
    path = "/track/?#{query}"

    http = Net::HTTP.new("127.0.0.1", PORT)
    req = Net::HTTP::Get.new(path, { 'origin' => 'http://foo.example' })
    http.request(req)
  end

  def include_http_header?(record)
    record.keys.find { |header| header.start_with?('HTTP_') }
  end
end
