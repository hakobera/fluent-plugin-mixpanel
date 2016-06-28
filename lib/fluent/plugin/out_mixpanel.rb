
class Fluent::MixpanelOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('mixpanel', self)

  include Fluent::HandleTagNameMixin

  config_param :project_token, :string
  config_param :api_key, :string, :default => ''
  config_param :use_import, :bool, :default => nil
  config_param :distinct_id_key, :string
  config_param :event_key, :string, :default => nil
  config_param :ip_key, :string, :default => nil
  config_param :event_map_tag, :bool, :default => false
  #NOTE: This will be removed in a future release. Please specify the '.' on any prefix
  config_param :use_legacy_prefix_behavior, :default => true

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

    if @event_key.nil? and !@event_map_tag
      raise Fluent::ConfigError, "'event_key' must be specifed when event_map_tag == false."
    end
  end

  def start
    super
    @tracker = Mixpanel::Tracker.new(@project_token)
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
        log.warn("no event, record: #{record.to_json}")
        next
      end

      # Ignore browswer only special event
      next if data['event'].start_with?('mp_')

      if record[@distinct_id_key]
        data['distinct_id'] = record[@distinct_id_key]
        prop.delete(@distinct_id_key)
      else
        log.warn("no distinct_id, record: #{record.to_json}")
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
    records.each do |record|
     success = 	if @use_import
        					@tracker.import(@api_key, record['distinct_id'], record['event'], record['properties'])
      					else
        					@tracker.track(record['distinct_id'], record['event'], record['properties'])
      					end
      raise MixpanelError.new("Failed to track event to mixpanel") unless success
    end
  end
end
