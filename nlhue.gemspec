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

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_runtime_dependency 'eventmachine', '~> 1.0'
  spec.add_runtime_dependency 'UPnP', '~> 1.2'
end
