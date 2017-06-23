$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "rails_ebi/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "rails_ebi"
  s.version     = RailsEbi::VERSION
  s.authors     = ["KhiemNS"]
  s.email       = ["khiemns.k54@gmail.com"]
  s.homepage    = "TODO"
  s.summary     = "TODO: Deploy rails app to Elastic Beanstalk."
  s.description = "TODO: Deploy rails app to Elastic Beanstalk via rake task with switchable ebextensions and Docker.run.json"
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  s.add_dependency "rails", "~> 5.0.2"
  s.add_dependency "rubyzip", "~> 1.2.1"
  s.add_dependency "aws-sdk", "~> 2.10.2"
  s.add_dependency "dotenv", "~> 2.2.1"
end
