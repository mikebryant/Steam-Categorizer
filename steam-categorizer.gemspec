# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'steam/categorizer/version'

Gem::Specification.new do |spec|
  spec.name          = "steam-categorizer"
  spec.version       = Steam::Categorizer::VERSION
  spec.authors       = ["Lyle Tafoya"]
  spec.email         = ["lyle.tafoya@gmail.com"]

  spec.summary       = "Automatically generate categories for games in your Steam library"
  spec.homepage      = "TODO: Put your gem's website or public repo URL here."

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "httparty", "~> 0.13"
  spec.add_runtime_dependency "json", "~> 1.8"
  spec.add_runtime_dependency "nokogiri", "~> 1.6"
  spec.add_runtime_dependency "ruby-progressbar", "~> 1.7"
  spec.add_runtime_dependency "vdf4r", "~> 0.2"
  spec.add_runtime_dependency "trollop", "~> 2.1"

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
end