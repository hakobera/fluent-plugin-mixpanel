require 'helper'
require 'uri'
require 'msgpack'
require 'fluent/plugin/out_mixpanel'

class MixpanelOutputTest < Test::Unit::TestCase

  def setup
    Fluent::Test.setup
    @out = []
  end

  CONFIG = %[
    project_token test_token
    distinct_id_key user_id
    log_level info
  ]

  IMPORT_CONFIG = CONFIG + %[ api_key test_api_key
                              use_import true
                              use_legacy_prefix_behavior false
                            ]

  def create_driver(conf = CONFIG)
    Fluent::Test::BufferedOutputTestDriver.new(Fluent::MixpanelOutput, 'mixpanel.test').configure(conf)
  end

  def stub_mixpanel(url='https://api.mixpanel.com/track')
    stub_request(:post, url).with do |req|
      body = URI.decode_www_form(req.body)
      @out << JSON.load(Base64.decode64(body.assoc('data').last))
    end.to_return(status: 200, body: JSON.generate({ status: 1 }))
  end

  def stub_mixpanel_import
    stub_mixpanel('https://api.mixpanel.com/import')
  end

  def stub_mixpanel_unavailable(url='https://api.mixpanel.com/track')
    stub_request(:post, url).to_return(status: 503, body: 'Service Unavailable')
  end

  def sample_record
    { user_id: '123', event: 'event1', key1: 'value1', key2: 'value2' }
  end

  def test_configure
    d = create_driver(CONFIG + 'event_key event')

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
    d = create_driver(CONFIG + 'event_map_tag true')

    assert_equal 'test_token', d.instance.project_token
    assert_equal 'user_id', d.instance.distinct_id_key
    assert_equal nil, d.instance.event_key
    assert_equal true.to_s, d.instance.event_map_tag
  end

  def test_write
    stub_mixpanel
    d = create_driver(CONFIG + 'event_key event')
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record, time)
    d.run

    assert_equal 'test_token', @out[0]['properties']['token']
    assert_equal '123',     @out[0]['properties']['distinct_id']
    assert_equal 'event1',  @out[0]['event']
    assert_equal time, @out[0]['properties']['time']
    assert_equal 'value1',  @out[0]['properties']['key1']
    assert_equal 'value2',  @out[0]['properties']['key2']
  end

  def test_write_setting_time_via_export
    stub_mixpanel_import
    d = create_driver(CONFIG + "use_import true\nevent_key event")
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record.merge!('time' => 1435707767), time)
    d.run

    assert_equal 'test_token', @out[0]['properties']['token']
    assert_equal '123',     @out[0]['properties']['distinct_id']
    assert_equal 'event1',  @out[0]['event']
    assert_equal 1435707767, @out[0]['properties']['time']
    assert_equal 'value1',  @out[0]['properties']['key1']
    assert_equal 'value2',  @out[0]['properties']['key2']
  end

  def test_write_multi_request
    stub_mixpanel_import
    d = create_driver(IMPORT_CONFIG + 'event_key event')
    time1 = Time.new('2014-01-01T01:23:45+00:00').to_i
    time2 = Time.new('2014-01-02T01:23:45+00:00').to_i

    d.emit(sample_record, time1)
    d.emit(sample_record.merge(key3: 'value3'), time2)
    d.run

    assert_equal '123',      @out[0]['properties']['distinct_id']
    assert_equal 'event1',   @out[0]['event']
    assert_equal time1, @out[0]['properties']['time']
    assert_equal 'value1',   @out[0]['properties']['key1']
    assert_equal 'value2',   @out[0]['properties']['key2']

    assert_equal '123',      @out[1]['properties']['distinct_id']
    assert_equal 'event1',   @out[1]['event']
    assert_equal time2, @out[1]['properties']['time']
    assert_equal 'value1',   @out[1]['properties']['key1']
    assert_equal 'value2',   @out[1]['properties']['key2']
    assert_equal 'value2',   @out[1]['properties']['key2']
  end

  def test_write_with_ip_key
    stub_mixpanel
    d = create_driver(CONFIG + "event_key event\n ip_key ip_address")
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record.merge('ip_address' => '192.168.0.2'), time)
    d.run

    assert_equal '123',         @out[0]['properties']['distinct_id']
    assert_equal 'event1',      @out[0]['event']
    assert_equal time,     @out[0]['properties']['time']
    assert_equal '192.168.0.2', @out[0]['properties']['ip']
    assert_equal 'value1',      @out[0]['properties']['key1']
    assert_equal 'value2',      @out[0]['properties']['key2']
  end

  def test_write_with_no_tag_manipulation
    stub_mixpanel
    d = create_driver(CONFIG + 'event_map_tag true')
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record, time)
    d.run

    assert_equal '123',           @out[0]['properties']['distinct_id']
    assert_equal 'mixpanel.test', @out[0]['event']
    assert_equal time,       @out[0]['properties']['time']
    assert_equal 'value1',        @out[0]['properties']['key1']
    assert_equal 'value2',        @out[0]['properties']['key2']
  end

  def test_write_with_event_map_tag_removing_prefix
    stub_mixpanel
    d = create_driver(CONFIG + "remove_tag_prefix mixpanel.\n event_map_tag true")
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record, time)
    d.run

    assert_equal '123',     @out[0]['properties']['distinct_id']
    assert_equal 'test',    @out[0]['event']
    assert_equal time, @out[0]['properties']['time']
    assert_equal 'value1',  @out[0]['properties']['key1']
    assert_equal 'value2',  @out[0]['properties']['key2']
  end

  def test_write_with_event_map_tag_removing_prefix_LEGACY
    stub_mixpanel
    d = create_driver(CONFIG + "remove_tag_prefix mixpanel\n event_map_tag true\n use_legacy_prefix_behavior true")
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record, time)
    d.run

    assert_equal '123',     @out[0]['properties']['distinct_id']
    assert_equal 'test',    @out[0]['event']
    assert_equal time, @out[0]['properties']['time']
    assert_equal 'value1',  @out[0]['properties']['key1']
    assert_equal 'value2',  @out[0]['properties']['key2']
  end

  def test_write_with_event_map_tag_removing_prefix_LEGACY_with_dot
    stub_mixpanel
    d = create_driver(CONFIG + "remove_tag_prefix mixpanel.\n event_map_tag true\n use_legacy_prefix_behavior true")
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record, time)
    d.run

    assert_equal '123',     @out[0]['properties']['distinct_id']
    assert_equal 'test',    @out[0]['event']
    assert_equal time, @out[0]['properties']['time']
    assert_equal 'value1',  @out[0]['properties']['key1']
    assert_equal 'value2',  @out[0]['properties']['key2']
  end

  def test_write_with_event_map_tag_removing_suffix
    stub_mixpanel
    d = create_driver(CONFIG + "remove_tag_suffix .test\n event_map_tag true")
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record, time)
    d.run

    assert_equal '123',     @out[0]['properties']['distinct_id']
    assert_equal 'mixpanel',    @out[0]['event']
    assert_equal time, @out[0]['properties']['time']
    assert_equal 'value1',  @out[0]['properties']['key1']
    assert_equal 'value2',  @out[0]['properties']['key2']
  end

  def test_write_with_event_map_tag_adding_prefix
    stub_mixpanel
    d = create_driver(CONFIG + "add_tag_prefix foo.\n event_map_tag true")
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record, time)
    d.run

    assert_equal '123',     @out[0]['properties']['distinct_id']
    assert_equal 'foo.mixpanel.test',    @out[0]['event']
    assert_equal time, @out[0]['properties']['time']
    assert_equal 'value1',  @out[0]['properties']['key1']
    assert_equal 'value2',  @out[0]['properties']['key2']
  end

  def test_write_with_event_map_tag_adding_suffix
    stub_mixpanel
    d = create_driver(CONFIG + "add_tag_suffix .foo\n event_map_tag true")
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record, time)
    d.run

    assert_equal '123',     @out[0]['properties']['distinct_id']
    assert_equal 'mixpanel.test.foo',    @out[0]['event']
    assert_equal time, @out[0]['properties']['time']
    assert_equal 'value1',  @out[0]['properties']['key1']
    assert_equal 'value2',  @out[0]['properties']['key2']
  end

  def test_write_ignore_special_event
    stub_mixpanel
    d = create_driver(CONFIG + 'event_key event')
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit({ user_id: '123', event: 'mp_page_view' }, time)
    d.run

    assert_equal 0, @out.length
  end

  def test_write_ignore_special_property
    stub_mixpanel
    d = create_driver(CONFIG + 'event_key event')
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record.merge('mp_event' => '3'), time)
    d.run

    assert_equal 'test_token', @out[0]['properties']['token']
    assert_equal '123',     @out[0]['properties']['distinct_id']
    assert_equal 'event1',  @out[0]['event']
    assert_equal time, @out[0]['properties']['time']
    assert_equal 'value1',  @out[0]['properties']['key1']
    assert_equal 'value2',  @out[0]['properties']['key2']
    assert_equal false, @out[0]['properties'].key?('mp_event')
  end

  def test_write_delete_supried_token
    stub_mixpanel
    d = create_driver(CONFIG + 'event_key event')
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record.merge('token' => '123'), time)
    d.run

    assert_equal 'test_token', @out[0]['properties']['token']
    assert_equal '123',     @out[0]['properties']['distinct_id']
    assert_equal 'event1',  @out[0]['event']
    assert_equal time, @out[0]['properties']['time']
    assert_equal 'value1',  @out[0]['properties']['key1']
    assert_equal 'value2',  @out[0]['properties']['key2']
    assert_equal false, @out[0]['properties'].key?('mp_event')
  end

  def test_request_error
    stub_mixpanel_unavailable
    d = create_driver(CONFIG + 'event_key event')
    d.emit(sample_record)
    assert_raise(Fluent::MixpanelOutput::MixpanelError) {
      d.run
    }
  end

  def test_multiple_records_1_missing_event
    stub_mixpanel
    d = create_driver(CONFIG + 'event_key event')
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record, time)

    broken_record = sample_record.dup.delete(:event)
    d.emit(broken_record, time)

    d.run

    assert_equal 1, @out.length

    assert_equal 'test_token', @out[0]['properties']['token']
    assert_equal '123',     @out[0]['properties']['distinct_id']
    assert_equal 'event1',  @out[0]['event']
    assert_equal time, @out[0]['properties']['time']
    assert_equal 'value1',  @out[0]['properties']['key1']
    assert_equal 'value2',  @out[0]['properties']['key2']

  end

  def test_multiple_records_1_missing_distinct_id
    stub_mixpanel
    d = create_driver(CONFIG + 'event_key event')
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record, time)

    broken_record = sample_record.dup.delete(:user_id)
    d.emit(broken_record, time)

    d.run

    assert_equal 1, @out.length

    assert_equal 'test_token', @out[0]['properties']['token']
    assert_equal '123',     @out[0]['properties']['distinct_id']
    assert_equal 'event1',  @out[0]['event']
    assert_equal time, @out[0]['properties']['time']
    assert_equal 'value1',  @out[0]['properties']['key1']
    assert_equal 'value2',  @out[0]['properties']['key2']

  end

  def test_multiple_records_1_having_mp
    stub_mixpanel
    d = create_driver(CONFIG + 'event_key event')
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record, time)

    broken_record = sample_record.dup.merge({ event: 'mp_foo'})
    d.emit(broken_record, time)

    d.run

    assert_equal 1, @out.length

    assert_equal 'test_token', @out[0]['properties']['token']
    assert_equal '123',     @out[0]['properties']['distinct_id']
    assert_equal 'event1',  @out[0]['event']
    assert_equal time, @out[0]['properties']['time']
    assert_equal 'value1',  @out[0]['properties']['key1']
    assert_equal 'value2',  @out[0]['properties']['key2']

  end

  def test_request_error_discard
    stub_mixpanel_unavailable
    d = create_driver(CONFIG + "event_key event\ndiscard_event_on_send_error true")
    time = Time.new('2014-01-01T01:23:45+00:00').to_i
    d.emit(sample_record, time)
    d.run

    logs = d.instance.log.logs

    assert_match 'MixpanelOutputErrorHandler:', logs[0]
    assert_match 'Class: Mixpanel::ServerError', logs[0]
    assert_match "Message: Could not write to Mixpanel, server responded with 503 returning: 'Service Unavailable", logs[0]
    assert_match 'Backtrace', logs[0]
    assert_match 'Failed to track event to mixpanel', logs[1]
    assert_match 'Record: {"properties":{"key1":"value1","key2":"value2","time":' + time.to_s + '},"event":"event1","distinct_id":"123"}', logs[1]
  end


  def test_mixpanel_batch
    stub_mixpanel
    d = create_driver(CONFIG + "event_key event\nbatch_to_mixpanel true\n")
    time1 = Time.new('2014-01-01T01:23:45+00:00').to_i
    time2 = Time.new('2014-01-02T01:23:45+00:00').to_i

    d.emit(sample_record, time1)
    d.emit(sample_record.merge(key3: 'value3'), time2)
    d.run

    #Because of the batching, @out is an array with a single element, that being an array of two events
    #  compared to non-batched tests, where @out is just an array of the events
    # Therefore this structure is a good indication that the batching is actually working
    assert_equal 1, @out.length
    batch = @out[0]
    assert_equal 2, batch.length
    assert_equal '123',      batch[0]['properties']['distinct_id']
    assert_equal 'event1',   batch[0]['event']
    assert_equal time1, batch[0]['properties']['time']
    assert_equal 'value1',   batch[0]['properties']['key1']
    assert_equal 'value2',   batch[0]['properties']['key2']

    assert_equal '123',      batch[1]['properties']['distinct_id']
    assert_equal 'event1',   batch[1]['event']
    assert_equal time2, batch[1]['properties']['time']
    assert_equal 'value1',   batch[1]['properties']['key1']
    assert_equal 'value2',   batch[1]['properties']['key2']
    assert_equal 'value3',   batch[1]['properties']['key3']
  end

  def test_mixpanel_batch_profile_update
    stub_mixpanel
    d = create_driver(CONFIG + "event_key event\nbatch_to_mixpanel true\n")
    time1 = Time.new('2014-01-01T01:23:45+00:00').to_i
    time2 = Time.new('2014-01-02T01:23:45+00:00').to_i

    d.emit(sample_record.merge(event_type: 'profile_update'), time1)
    d.emit({event_type: 'profile_inc', event: '', user_id: '123', value: 1}, time2)
    d.run

    #Because of the batching, @out is an array with a single element, that being an array of two events
    #  compared to non-batched tests, where @out is just an array of the events
    # Therefore this structure is a good indication that the batching is actually working
    assert_equal 1, @out.length
    batch = @out[0]
    assert_equal 2, batch.length
    assert_equal '123',      batch[0]['properties']['distinct_id']
    assert_equal 'event1',   batch[0]['event']
    assert_equal time1, batch[0]['properties']['time']
    assert_equal 'value1',   batch[0]['properties']['key1']
    assert_equal 'value2',   batch[0]['properties']['key2']

    assert_equal '123',      batch[1]['properties']['distinct_id']
    assert_equal time2, batch[1]['properties']['time']
    assert_equal 1,   batch[1]['properties']['value']
  end
end
