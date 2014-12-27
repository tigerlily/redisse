# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'redisse/version'

Gem::Specification.new do |spec|
  spec.name          = "redisse"
  spec.version       = Redisse::VERSION
  spec.authors       = ["Étienne Barrié", "Julien Blanchard"]
  spec.email         = ["etienne.barrie@gmail.com", "julien@sideburns.eu"]
  spec.summary       = %q{Server-Sent Events via Redis}
  spec.homepage      = "https://github.com/tigerlily/redisse"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.1"
  spec.add_development_dependency "rspec-core", "~> 3.1.6"
  spec.add_development_dependency "yard-tomdoc"
  spec.add_development_dependency "rack-test"
  spec.add_development_dependency "dotenv"
  spec.add_runtime_dependency "goliath"
  spec.add_runtime_dependency "eventmachine", "~> 1.0.4"
  spec.add_runtime_dependency "em-hiredis"
  spec.add_runtime_dependency "redis"
end
