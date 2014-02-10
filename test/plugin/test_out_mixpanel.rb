require 'helper'
require 'uri'
require 'webmock/test_unit'

WebMock.disable_net_connect!

class MixpanelOutputTest < Test::Unit::TestCase

  def setup
    Fluent::Test.setup
    @out = []
  end

  CONFIG = %[
    project_token test_token
    distinct_id_key user_id
    event_key event
  ]

  def create_driver(conf = CONFIG)
    Fluent::Test::BufferedOutputTestDriver.new(Fluent::MixpanelOutput).configure(conf)
  end

  def stub_mixpanel(url="https://api.mixpanel.com/track")
    stub_request(:post, url).with do |req|
      body = URI.decode_www_form(req.body)
      @out << JSON.load(Base64.decode64(body.assoc('data').last))
    end.to_return(status: 200, body: JSON.generate({ status: 1 }))
  end

  def stub_mixpanel_unavailable(url="https://api.mixpanel.com/track")
    stub_request(:post, url).to_return(status: 503, body: "Service Unavailable")
  end

  def sample_record
    { user_id: "123", event: "event1", key1: "value1", key2: "value2" }
  end

  def test_configure
    d = create_driver

    assert_equal 'test_token', d.instance.project_token
    assert_equal 'user_id', d.instance.distinct_id_key
    assert_equal 'event', d.instance.event_key
  end

  def test_write
    stub_mixpanel
    d = create_driver
    time = Time.new('2014-01-01T01:23:45+00:00')
    d.emit(sample_record, time)
    d.run

    assert_equal "123",     @out[0]['properties']['distinct_id']
    assert_equal "event1",  @out[0]['event']
    assert_equal time.to_i, @out[0]['properties']['time']
    assert_equal "value1",  @out[0]['properties']['key1']
    assert_equal "value2",  @out[0]['properties']['key2']
  end

  def test_write_multi_request
    stub_mixpanel
    d = create_driver
    time1 = Time.new('2014-01-01T01:23:45+00:00')
    time2 = Time.new('2014-01-02T01:23:45+00:00')

    d.emit(sample_record, time1)
    d.emit(sample_record.merge(key3: "value3"), time2)
    d.run

    assert_equal "123",      @out[0]['properties']['distinct_id']
    assert_equal "event1",   @out[0]['event']
    assert_equal time1.to_i, @out[0]['properties']['time']
    assert_equal "value1",   @out[0]['properties']['key1']
    assert_equal "value2",   @out[0]['properties']['key2']

    assert_equal "123",      @out[1]['properties']['distinct_id']
    assert_equal "event1",   @out[1]['event']
    assert_equal time2.to_i, @out[1]['properties']['time']
    assert_equal "value1",   @out[1]['properties']['key1']
    assert_equal "value2",   @out[1]['properties']['key2']
    assert_equal "value2",   @out[1]['properties']['key2']
  end

  def test_request_error
    stub_mixpanel_unavailable
    d = create_driver
    d.emit(sample_record)
    assert_raise(Mixpanel::ConnectionError) {
      d.run
    }
  end
end
