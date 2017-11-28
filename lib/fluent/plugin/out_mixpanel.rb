require_relative "mixpanel_ruby_error_handler.rb"

class Fluent::MixpanelOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('mixpanel', self)

  include Fluent::HandleTagNameMixin

  config_param :project_token, :string, :secret => true
  config_param :api_key, :string, :default => '', :secret => true
  config_param :use_import, :bool, :default => nil
  config_param :distinct_id_key, :string
  config_param :event_key, :string, :default => nil
  config_param :ip_key, :string, :default => nil
  config_param :event_map_tag, :bool, :default => false
  #NOTE: This will be removed in a future release. Please specify the '.' on any prefix
  config_param :use_legacy_prefix_behavior, :default => true
  config_param :discard_event_on_send_error, :default => false
  config_param :batch_to_mixpanel, :default => false

  class MixpanelError < StandardError
  end

  def initialize
    super
    require 'mixpanel-ruby'
  end

  def configure(conf)
    super
    @project_tokey = conf['project_token']
    @distinct_id_key = conf['distinct_id_key']
    @event_key = conf['event_key']
    @ip_key = conf['ip_key']
    @event_map_tag = conf['event_map_tag']
    @api_key = conf['api_key']
    @use_import = conf['use_import']
    @use_legacy_prefix_behavior = conf['use_legacy_prefix_behavior']
    @discard_event_on_send_error = conf['discard_event_on_send_error']
    @batch_to_mixpanel = conf['batch_to_mixpanel']

    if @event_key.nil? and !@event_map_tag
      raise Fluent::ConfigError, "'event_key' must be specifed when event_map_tag == false."
    end
  end

  def start
    super
    error_handler = Fluent::MixpanelOutputErrorHandler.new(log)
    if(@batch_to_mixpanel)
      @batched_consumer = Mixpanel::BufferedConsumer.new
      @tracker = Mixpanel::Tracker.new(@project_token, error_handler) do | type, message |
          @batched_consumer.send!(type, message)
      end
    else
      @tracker = Mixpanel::Tracker.new(@project_token, error_handler)
    end
  end

  def shutdown
    super
  end

  def format(tag, time, record)
    time = record['time'] if record['time'] && @use_import
    [tag, time, record].to_msgpack
  end

  def write(chunk)
    records = []
    chunk.msgpack_each do |tag, time, record|
      data = {}
      prop = data['properties'] = record.dup

      # Ignore token in record
      prop.delete('token')

      if @event_map_tag
        tag.gsub!(/^\./, '') if @use_legacy_prefix_behavior
        data['event'] = tag
      elsif record[@event_key]
        data['event'] = record[@event_key]
        prop.delete(@event_key)
      else
        log.warn("no event, tag: #{tag}, time: #{time.to_s}, record: #{record.to_json}")
        next
      end

      # Ignore browswer only special event
      next if data['event'].start_with?('mp_')

      if record[@distinct_id_key]
        data['distinct_id'] = record[@distinct_id_key]
        prop.delete(@distinct_id_key)
      else
        log.warn("no distinct_id, tag: #{tag}, time: #{time.to_s}, record: #{record.to_json}")
        next
      end

      if !@ip_key.nil? and record[@ip_key]
        prop['ip'] = record[@ip_key]
        prop.delete(@ip_key)
      end

      prop.select! {|key, _| !key.start_with?('mp_') }
      prop.merge!('time' => time.to_i)

      records << data
    end

    send_to_mixpanel(records)
  end

  def send_to_mixpanel(records)
    log.debug("sending #{records.length} to mixpanel")

    records.each do |record|
      success = true

      if @use_import
        success = @tracker.import(@api_key, record['distinct_id'], record['event'], record['properties'])
      else
        success = @tracker.track(record['distinct_id'], record['event'], record['properties'])
      end

      unless success
        if @discard_event_on_send_error
          msg = "Failed to track event to mixpanel:\n"
          msg += "\tRecord: #{record.to_json}"
          log.info(msg)
        else
          raise MixpanelError.new("Failed to track event to mixpanel")
        end
      end
    end
    if(@batch_to_mixpanel)
      @batched_consumer.flush
    end
  end
end
