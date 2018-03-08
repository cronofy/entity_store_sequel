$:.push File.expand_path("../lib", __FILE__)
require "entity_store_sequel/version"

Gem::Specification.new do |s|
  s.name        = "entity_store_sequel"
  s.version     = EntityStoreSequel::VERSION.dup
  s.platform    = Gem::Platform::RUBY
  s.summary     = "Sequel body for Entity Store"
  s.email       = "stephen@cronofy.com"
  s.homepage    = "http://github.com/cronofy/entity_store_sequel"
  s.description = "Sequel body for Entity Store"
  s.authors     = ['Stephen Binns']
  s.license     = 'MIT'

  s.files         = Dir["lib/**/*"]
  s.test_files    = Dir["spec/**/*"]
  s.require_paths = ["lib"]

  s.add_dependency('sequel')
  s.add_dependency('entity_store')
  s.add_dependency('pigeon_hole', '~> 0.1.0')
  s.add_dependency('bson', '~> 3.0')
  s.add_dependency('hatchet', '~> 0.2')
end
