# frozen_string_literal: true

require File.expand_path("./lib/spyder/version", __dir__)

Gem::Specification.new do |s|
  s.name        = 'spyder'
  s.version     = ::Spyder::VERSION
  s.summary     = "Spyder"
  s.description = "Spyder Web"
  s.author      = "André D. Piske"
  s.email       = 'andrepiske@gmail.com'
  s.homepage    = 'https://github.com/andrepiske/spyder'
  s.licenses    = ['MIT']

  s.files       = Dir.glob([ "lib/**/*.rb" ])
  s.executables = []

  s.add_runtime_dependency 'mustermann', '~> 3.0'
  # s.add_runtime_dependency 'multi_json', '< 2'
  # s.add_runtime_dependency 'redis', '>= 3.0.5'
  # s.add_runtime_dependency 'msgpack', '~> 1.3'
  # s.add_runtime_dependency 'connection_pool', '>= 2.2.2', '< 3'
  # s.add_runtime_dependency 'concurrent-ruby', '~> 1.1.6'

  # spyder-web dependencies:
  s.add_runtime_dependency 'marcel', '~> 1.0'
end
