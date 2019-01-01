$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "ted/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "the_energy_detective"
  s.version     = TED::VERSION
  s.authors     = ["Cody Cutrer"]
  s.email       = ["cody@cutrer.us"]
  s.homepage    = "http://www.theenergydetective.com/"
  s.summary     = "Client library for talking to a TED Home Pro"
  s.license     = "MIT"

  s.files = Dir["{lib}/**/*"] + ["Rakefile"]
  s.test_files = Dir["spec/**/*"]

  s.add_dependency 'nokogiri', '~> 1.9'

  s.add_development_dependency 'rake', '~> 12.3'
end
