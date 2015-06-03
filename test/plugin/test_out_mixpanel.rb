require 'helper'
require 'uri'

class MixpanelOutputTest < Test::Unit::TestCase

  def setup
    Fluent::Test.setup
    @out = []
  end

  CONFIG = %[
    project_token test_token
    distinct_id_key user_id
  ]

  IMPORT_CONFIG = CONFIG + %[ api_key test_api_key
                              use_import true
                              use_legacy_prefix_behavior false
                            ]

  def create_driver(conf = CONFIG)
    Fluent::Test::BufferedOutputTestDriver.new(Fluent::MixpanelOutput, 'mixpanel.test').configure(conf)
  end

  def stub_mixpanel(url="https://api.mixpanel.com/track")
    stub_request(:post, url).with do |req|
      body = URI.decode_www_form(req.body)
      @out << JSON.load(Base64.decode64(body.assoc('data').last))
    end.to_return(status: 200, body: JSON.generate({ status: 1 }))
  end

  def stub_mixpanel_import
    stub_mixpanel("https://api.mixpanel.com/import")
  end

  def stub_mixpanel_unavailable(url="https://api.mixpanel.com/track")
    stub_request(:post, url).to_return(status: 503, body: "Service Unavailable")
  end

  def sample_record
    { user_id: "123", event: "event1", key1: "value1", key2: "value2" }
  end

  def test_configure
    d = create_driver(CONFIG + "event_key event")

    assert_equal 'test_token', d.instance.project_token
    assert_equal 'user_id', d.instance.distinct_id_key
    assert_equal 'event', d.instance.event_key
  end

  def test_configure_with_ip_key
    d = create_driver(CONFIG + "event_key event\n ip_key ip")

    assert_equal 'test_token', d.instance.project_token
    assert_equal 'user_id', d.instance.distinct_id_key
    assert_equal 'event', d.instance.event_key
    assert_equal 'ip', d.instance.ip_key
  end

  def test_configure_with_event_map_tag
    d = create_driver(CONFIG + "event_map_tag true")

    assert_equal 'test_token', d.instance.project_token
    assert_equal 'user_id', d.instance.distinct_id_key
    assert_equal nil, d.instance.event_key
    assert_equal true.to_s, d.instance.event_map_tag
  end

  def test_write
    stub_mixpanel
    d = create_driver(CONFIG + "event_key event")
    time = Time.new('2014-01-01T01:23:45+00:00')
    d.emit(sample_record, time)
    d.run

    assert_equal "test_token", @out[0]['properties']['token']
    assert_equal "123",     @out[0]['properties']['distinct_id']
    assert_equal "event1",  @out[0]['event']
    assert_equal time.to_i, @out[0]['properties']['time']
    assert_equal "value1",  @out[0]['properties']['key1']
    assert_equal "value2",  @out[0]['properties']['key2']
  end

  def test_write_multi_request
    stub_mixpanel_import
    d = create_driver(IMPORT_CONFIG + "event_key event")
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

  def test_write_with_ip_key
    stub_mixpanel
    d = create_driver(CONFIG + "event_key event\n ip_key ip_address")
    time = Time.new('2014-01-01T01:23:45+00:00')
    d.emit(sample_record.merge('ip_address' => '192.168.0.2'), time)
    d.run

    assert_equal "123",         @out[0]['properties']['distinct_id']
    assert_equal "event1",      @out[0]['event']
    assert_equal time.to_i,     @out[0]['properties']['time']
    assert_equal "192.168.0.2", @out[0]['properties']['ip']
    assert_equal "value1",      @out[0]['properties']['key1']
    assert_equal "value2",      @out[0]['properties']['key2']
  end

  def test_write_with_no_tag_manipulation
    stub_mixpanel
    d = create_driver(CONFIG + "event_map_tag true")
    time = Time.new('2014-01-01T01:23:45+00:00')
    d.emit(sample_record, time)
    d.run

    assert_equal "123",           @out[0]['properties']['distinct_id']
    assert_equal "mixpanel.test", @out[0]['event']
    assert_equal time.to_i,       @out[0]['properties']['time']
    assert_equal "value1",        @out[0]['properties']['key1']
    assert_equal "value2",        @out[0]['properties']['key2']
  end

  def test_write_with_event_map_tag_removing_prefix
    stub_mixpanel
    d = create_driver(CONFIG + "remove_tag_prefix mixpanel.\n event_map_tag true")
    time = Time.new('2014-01-01T01:23:45+00:00')
    d.emit(sample_record, time)
    d.run

    assert_equal "123",     @out[0]['properties']['distinct_id']
    assert_equal "test",    @out[0]['event']
    assert_equal time.to_i, @out[0]['properties']['time']
    assert_equal "value1",  @out[0]['properties']['key1']
    assert_equal "value2",  @out[0]['properties']['key2']
  end

  def test_write_with_event_map_tag_removing_prefix_LEGACY
    stub_mixpanel
    d = create_driver(CONFIG + "remove_tag_prefix mixpanel\n event_map_tag true\n use_legacy_prefix_behavior true")
    time = Time.new('2014-01-01T01:23:45+00:00')
    d.emit(sample_record, time)
    d.run

    assert_equal "123",     @out[0]['properties']['distinct_id']
    assert_equal "test",    @out[0]['event']
    assert_equal time.to_i, @out[0]['properties']['time']
    assert_equal "value1",  @out[0]['properties']['key1']
    assert_equal "value2",  @out[0]['properties']['key2']
  end

  def test_write_with_event_map_tag_removing_suffix
    stub_mixpanel
    d = create_driver(CONFIG + "remove_tag_suffix .test\n event_map_tag true")
    time = Time.new('2014-01-01T01:23:45+00:00')
    d.emit(sample_record, time)
    d.run

    assert_equal "123",     @out[0]['properties']['distinct_id']
    assert_equal "mixpanel",    @out[0]['event']
    assert_equal time.to_i, @out[0]['properties']['time']
    assert_equal "value1",  @out[0]['properties']['key1']
    assert_equal "value2",  @out[0]['properties']['key2']
  end

  def test_write_with_event_map_tag_adding_prefix
    stub_mixpanel
    d = create_driver(CONFIG + "add_tag_prefix foo.\n event_map_tag true")
    time = Time.new('2014-01-01T01:23:45+00:00')
    d.emit(sample_record, time)
    d.run

    assert_equal "123",     @out[0]['properties']['distinct_id']
    assert_equal "foo.mixpanel.test",    @out[0]['event']
    assert_equal time.to_i, @out[0]['properties']['time']
    assert_equal "value1",  @out[0]['properties']['key1']
    assert_equal "value2",  @out[0]['properties']['key2']
  end

  def test_write_with_event_map_tag_adding_suffix
    stub_mixpanel
    d = create_driver(CONFIG + "add_tag_suffix .foo\n event_map_tag true")
    time = Time.new('2014-01-01T01:23:45+00:00')
    d.emit(sample_record, time)
    d.run

    assert_equal "123",     @out[0]['properties']['distinct_id']
    assert_equal "mixpanel.test.foo",    @out[0]['event']
    assert_equal time.to_i, @out[0]['properties']['time']
    assert_equal "value1",  @out[0]['properties']['key1']
    assert_equal "value2",  @out[0]['properties']['key2']
  end



  def test_write_ignore_special_event
    stub_mixpanel
    d = create_driver(CONFIG + "event_key event")
    time = Time.new('2014-01-01T01:23:45+00:00')
    d.emit({ user_id: '123', event: 'mp_page_view' }, time)
    d.run

    assert_equal 0, @out.length
  end

  def test_write_ignore_special_property
    stub_mixpanel
    d = create_driver(CONFIG + "event_key event")
    time = Time.new('2014-01-01T01:23:45+00:00')
    d.emit(sample_record.merge('mp_event' => '3'), time)
    d.run

    assert_equal "test_token", @out[0]['properties']['token']
    assert_equal "123",     @out[0]['properties']['distinct_id']
    assert_equal "event1",  @out[0]['event']
    assert_equal time.to_i, @out[0]['properties']['time']
    assert_equal "value1",  @out[0]['properties']['key1']
    assert_equal "value2",  @out[0]['properties']['key2']
    assert_equal false, @out[0]['properties'].key?('mp_event')
  end

  def test_write_delete_supried_token
    stub_mixpanel
    d = create_driver(CONFIG + "event_key event")
    time = Time.new('2014-01-01T01:23:45+00:00')
    d.emit(sample_record.merge('token' => '123'), time)
    d.run

    assert_equal "test_token", @out[0]['properties']['token']
    assert_equal "123",     @out[0]['properties']['distinct_id']
    assert_equal "event1",  @out[0]['event']
    assert_equal time.to_i, @out[0]['properties']['time']
    assert_equal "value1",  @out[0]['properties']['key1']
    assert_equal "value2",  @out[0]['properties']['key2']
    assert_equal false, @out[0]['properties'].key?('mp_event')
  end

  def test_request_error
    stub_mixpanel_unavailable
    d = create_driver(CONFIG + "event_key event")
    d.emit(sample_record)
    assert_raise(Fluent::MixpanelOutput::MixpanelError) {
      d.run
    }
  end
end
