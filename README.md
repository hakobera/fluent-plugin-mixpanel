# fluent-plugin-mixpanel

[![Build Status](https://travis-ci.org/hakobera/fluent-plugin-mixpanel.png?branch=master)](https://travis-ci.org/hakobera/fluent-plugin-mixpanel)

**CAUTION** This plugin does not support Ruby < 2.0

## Component

### MixpanelOutput

[Fluentd](http://fluentd.org) plugin to send event track data to [mixpanel](https://mixpanel.com).

### HttpMixpanelInput

[Fluentd](http://fluentd.org) plugin to integrate [mixpanel javascript libraries](https://mixpanel.com/docs/integration-libraries/javascript).

## Installation

Install with gem or fluent-gem command as:

```
# for fluentd
$ gem install fluent-plugin-mixpanel

# for td-agent
$ sudo /usr/lib64/fluent/ruby/bin/fluent-gem install fluent-plugin-mixpanel
```

## Configuration

### MixpanelOutput

MixpanelOutput needs mixpanel's `project_token`, that can get from your mixpanel project settings.

#### Use distinct_id_key and event_key

You should also specify property key name by `distinct_id_key` and `event_key`.

```
<match output.mixpanel.*>
  type mixpanel
  project_token YOUR_PROJECT_TOKEN
  distinct_id_key user_id
  event_key event_name
</match>
```

If record like this:

```rb
{ user_id: "123", event_name: "event1", key1: "value1", key2: "value2" }
```

above settings send to the following data to mixpanel, using [mixpanel-ruby](https://github.com/mixpanel/mixpanel-ruby) gem.

```rb
tracker = Mixpanel::Tracker.new(YOUR_PROJECT_TOKEN)
tracker.track("123", "event1", { key1: "value1", key2: "value2" })
```

#### Use distinct_id_key and event_map_tag

You can use tag name as event name like this. (see additional tag manipulations options below)

#### Discarding mixpanel errors

When delivering events to Mixpanel, Fluent creates a chunk of messages to send. By default, if one event fails to send to Mixpanel, all messages in that chunk are requeued for delivery. Enabling `discard_event_on_send_error` allows you to ignore single delivery failures. The event is logged via `info`, including the record being dropped.

```
<match output.mixpanel.*>
  ...
  discard_event_on_send_error true
  ...
</match>
```

##PLEASE NOTE (breaking api change in a future release)

The api for remove_tag_prefix will be changing in a future release. There is currently a boolean option,
use_legacy_prefix_behavior, which will ensure legacy behavior is maintained until that time. Eventually this option will go away
as well and the new behavior will be the only way. The difference is pretty simple, the '.' in the prefix needs to be specified.
This change allows this plugin to use Fluet's mixin and unifies syntax across plugins. Currently, use_legacy_prefix_behavior
defaults to true, which will work either way, but eventually you will need to specify the '.' in your prefix. Again, use_legacy_prefix_behavior simply removes any '.' along with the specified prefix and will behave properly even after you change your configs
to be current as seen below. You do not need to set this option.

```
<match output.mixpanel.*>
  type mixpanel
  project_token YOUR_PROJECT_TOKEN
  distinct_id_key user_id
  remove_tag_prefix output.mixpanel.
  event_map_tag true
</match>
```

If tag name is `output.mixpanel.event1` and record like this:

```rb
{ user_id: "123", key1: "value1", key2: "value2" }
```

above settings send to the following data to mixpanel, using [mixpanel-ruby](https://github.com/mixpanel/mixpanel-ruby) gem.

```rb
tracker = Mixpanel::Tracker.new(YOUR_PROJECT_TOKEN)
tracker.track("123", "event1", { key1: "value1", key2: "value2" })
```

#### Use the import method to post instead of track

You can use tag name as event name like this.

```
<match output.mixpanel.*>
  type mixpanel
  project_token YOUR_PROJECT_TOKEN
  distinct_id_key user_id
  remove_tag_prefix output.mixpanel.
  event_map_tag true
  use_import true
  api_key YOUR_API_KEY
</match>
```

If tag name is `output.mixpanel.event1` and record like this:

```rb
{ user_id: "123", key1: "value1", key2: "value2" }
```

above settings send to the following data to mixpanel, using [mixpanel-ruby](https://github.com/mixpanel/mixpanel-ruby) gem.

```rb
tracker = Mixpanel::Tracker.new(YOUR_PROJECT_TOKEN)
tracker.import(api_key, "123", "event1", { key1: "value1", key2: "value2" })
```

---

fluentd-plugin-mixpanel also includes the HandleTagNameMixin mixin which allows the following additional options:

```
remove_tag_prefix <tag_prefix_to_remove_including_the_dot>
remove_tag_suffix <tag_suffix_to_remove_including_the_dot>
add_tag_prefix <tag_prefix_to_add_including_the_dot>
add_tag_suffix <tag_suffix_to_add_including_the_dot>
```

### HttpMixpanelInput

HttpMixpanelInput has same configuration as [http Input Plugin](http://docs.fluentd.org/en/articles/in_http).

```
<source>
  type http_mixpanel
  bind 127.0.0.1
  port 8888
  body_size_limit 10m
  keepalive_timeout 5
  add_http_headers true
</source>
```

In example folder, you can see example configuration and HTML.

## Contributing

1. Fork it ( http://github.com/hakobera/fluent-plugin-mixpanel/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
