require 'helper'
require 'net/http'
require 'base64'

class HttpMixpanelInputTest < Test::Unit::TestCase
  
  def setup
    Fluent::Test.setup
  end

  PORT = unused_port
  CONFIG = %[
    port #{PORT}
    bind 127.0.0.1
    body_size_limit 10m
    keepalive_timeout 5
    access_control_allow_origin http://foo.example
  ]

  def create_driver(conf=CONFIG)
    Fluent::Test::InputTestDriver.new(Fluent::HttpMixpanelInput).configure(conf)
  end

  def test_configure
    d = create_driver
    assert_equal PORT, d.instance.port
    assert_equal '127.0.0.1', d.instance.bind
    assert_equal 10*1024*1024, d.instance.body_size_limit
    assert_equal 5, d.instance.keepalive_timeout
    assert_equal false, d.instance.add_http_headers    
    assert_equal 'http://foo.example', d.instance.access_control_allow_origin
  end

  def test_time
    d = create_driver

    time = Time.parse("2011-01-02 13:14:15 UTC").to_i
    Fluent::Engine.now = time

    d.expect_emit "mixpanel.tag1", time, {"a"=>1}
    d.expect_emit "mixpanel.tag2", time, {"a"=>2}

    d.run do
      d.expected_emits.each {|tag,time,record|
        res = track("#{tag}", {"json"=>record})
        assert_equal "200", res.code
        assert_equal 'true', res.header['access-control-allow-credentials']
        assert_equal 'X-Requested-With', res.header['access-control-allow-headers']
        assert_equal 'GET, POST, OPTIONS', res.header['access-control-allow-methods']
        assert_equal d.instance.access_control_allow_origin, res.header['access-control-allow-origin']
        assert_equal '1728000', res.header['access-control-max-age']
        assert_equal 'no-cache, no-store', res.header['cache-control']
      }
    end
  end

  def test_json
    d = create_driver

    time = Time.parse("2011-01-02 13:14:15 UTC").to_i

    d.expect_emit "mixpanel.tag1", time, {"a"=>1}
    d.expect_emit "mixpanel.tag2", time, {"a"=>2}

    d.run do
      d.expected_emits.each {|tag,time,record|
        res = track("#{tag}", {"json"=>record, "time"=>time.to_s})
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
      records.each {|tag,time,record|
        res = track("#{tag}", {"json"=>record, "time"=>time.to_s})
        assert_equal "200", res.code
      }
    end

    d.emit_streams.each { |tag, es|
      assert include_http_header?(es.first[1])
    }
  end

  def track(tag, params)
    event = tag.sub(/^mixpanel\.(.+)$/, '\1')
    params['json']['time'] = params['time'] if params['time']
    data = {
      event: event,
      properties: params['json']
    }
    data = URI.escape(Base64.encode64(data.to_json))
    query = "data=#{data}"
    path = "/track/?#{query}"

    http = Net::HTTP.new("127.0.0.1", PORT)
    req = Net::HTTP::Get.new(path)
    http.request(req)
  end

  def include_http_header?(record)
    record.keys.find { |header| header.start_with?('HTTP_') }
  end
end
