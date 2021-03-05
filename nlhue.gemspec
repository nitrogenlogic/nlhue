# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'nlhue/version'

Gem::Specification.new do |spec|
  spec.name          = "nlhue"
  spec.version       = NLHue::VERSION
  spec.authors       = ["Mike Bourgeous"]
  spec.email         = ["mike@nitrogenlogic.com"]

  spec.summary       = %q{An EventMachine-based library for interfacing with the Philips Hue lighting system.}
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/nitrogenlogic/nlhue"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 2.1"
  spec.add_development_dependency "rake", "~> 13.0.1"
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'pry-byebug'

  spec.add_runtime_dependency 'eventmachine', '~> 1.0'

  # TODO: Update to easy_upnp; UPnP homepage is gone and the gem hasn't been
  # updated since 2009
  spec.add_runtime_dependency 'UPnP', '~> 1.2'
end
