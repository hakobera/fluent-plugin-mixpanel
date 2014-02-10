# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-mixpanel"
  spec.version       = "0.0.1"
  spec.authors       = ["Kazuyuki Honda"]
  spec.email         = ["hakobera@gmail.com"]
  spec.summary       = %q{Output data to mixpanel plugin for fluentd}
  spec.description   = %q{Output data to mixpanel plugin for fluentd}
  spec.homepage      = "https://github.com/hakobera/fluent-plugin-mixpanel"
  spec.license       = "Apache License v2.0"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "fluentd"
  spec.add_development_dependency "rake"
end
