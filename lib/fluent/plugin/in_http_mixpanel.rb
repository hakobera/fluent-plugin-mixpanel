require 'fluent/plugin/in_http'
require 'base64'

class Fluent::HttpMixpanelInput < Fluent::Plugin::HttpInput
  Fluent::Plugin.register_input('http_mixpanel', self)

  config_param :tag_prefix, :default => 'mixpanel'

  def configure(conf)
    compat_parameters_convert(conf, :inject, :extract, :parser, :formatter, default_chunk_key: "")
    super
  end

  def on_request(path_info, params)
    data = Base64.decode64(params['data']).force_encoding('utf-8')
    json = JSON.parse(data)
    props = json['properties']
    path = "/#{tag_prefix}.#{json['event']}"
    params['json'] = props.to_json
    params['time'] = props['time'].to_s if props['time']

    ret = super(path, params)
    
    headers = {
      'Access-Control-Allow-Credentials' => true,
      'Access-Control-Allow-Headers' => 'X-Requested-With',
      'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS',
      'Access-Control-Allow-Origin' => params['HTTP_ORIGIN'],
      'Access-Control-Max-Age' => 1728000,
      'Cache-Control' => 'no-cache, no-store',
      'Content-type' => 'text/plain'
    }

    [ret[0], headers, (ret[0] == '200 OK' ? '1' : '0')]
  end
end
