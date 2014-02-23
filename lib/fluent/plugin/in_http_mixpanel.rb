require 'fluent/plugin/in_http'
require 'base64'

class Fluent::HttpMixpanelInput < Fluent::HttpInput
  Fluent::Plugin.register_input('http_mixpanel', self)

  config_param :access_control_allow_origin
  config_param :tag_prefix, :default => 'mixpanel'

  def on_request(path_info, params)
    data = Base64.decode64(params['data']).force_encoding('utf-8')
    json = JSON.parse(data)
    path = "/#{tag_prefix}.#{json['event']}"
    params['json'] = json['properties'].to_json
    params['time'] = (params['_'].to_i / 1000).to_s if params['_']

    ret = super(path, params)
    
    headers = {
      'Access-Control-Allow-Credentials' => true,
      'Access-Control-Allow-Headers' => 'X-Requested-With',
      'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS',
      'Access-Control-Allow-Origin' => access_control_allow_origin,
      'Access-Control-Max-Age' => 1728000,
      'Cache-Control' => 'no-cache, no-store',
      'Content-type' => 'text/plain'
    }

    [ret[0], headers, (ret[0] == 200 ? 1 : 0)]
  end
end
