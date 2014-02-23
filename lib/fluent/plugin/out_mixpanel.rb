class Fluent::MixpanelOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('mixpanel', self)

  config_param :project_token, :string
  config_param :distinct_id_key, :string
  config_param :event_key, :string, :default => nil
  config_param :ip_key, :string, :default => nil

  config_param :remove_tag_prefix, :string, :default => nil
  config_param :event_map_tag, :bool, :default => false

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
    @remove_tag_prefix = conf['remove_tag_prefix']
    @event_map_tag = conf['event_map_tag']

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
    [tag, time, record].to_msgpack
  end

  def write(chunk)
    records = []
    chunk.msgpack_each do |tag, time, record|
      data = {}

      if record[@distinct_id_key]
        data['distinct_id'] = record[@distinct_id_key]
        record.delete(@distinct_id_key)
      else
        log.warn('no distinct_id')
        return
      end

      if @event_map_tag
        data['event'] = tag.gsub(/^#{@remove_tag_prefix}(\.)?/, '')
      elsif record[@event_key]
        data['event'] = record[@event_key]
        record.delete(@event_key)
      else 
        log.warn('no event')
        return
      end

      if !@ip_key.nil? and record[@ip_key]
        record['ip'] = record[@ip_key]
        record.delete(@ip_key)
      end

      record.merge!(time: time.to_i)
      data['properties'] = record
      
      records << data
    end

    records.each do |record|
      @tracker.track(record['distinct_id'], record['event'], record['properties'])
    end
  end
end
