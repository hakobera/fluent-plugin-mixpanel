class Fluent::MixpanelOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('mixpanel', self)

  config_param :project_token, :string
  config_param :distinct_id_key, :string
  config_param :event_key, :string

  def initialize
    super
    require 'mixpanel-ruby'
  end

  def configure(conf)
    super
    @project_tokey = conf['project_token']
    @distinct_id_key = conf['distinct_id_key']
    @event_key = conf['event_key']

    if @project_token.empty?
      raise Fluent::ConfigError, "'project_token' must be specifed."
    end

    if @distinct_id_key.empty?
      raise Fluent::ConfigError, "'distinct_id_key' must be specifed."
    end

    if @event_key.empty?
      raise Fluent::ConfigError, "'event_key' must be specifed."
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

      if record[@event_key]
        data['event'] = record[@event_key]
        record.delete(@event_key)
      else 
        log.warn('no event')
        return
      end

      data['properties'] = record
      
      records << data
    end

    records.each do |record|
      @tracker.track(record['distinct_id'], record['event'], record['properties'])
    end
  end
end
