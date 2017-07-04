$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "rebi/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "rebi"
  s.version     = Rebi::VERSION
  s.authors     = ["KhiemNS"]
  s.email       = ["khiemns.k54@gmail.com"]
  s.homepage    = "https://github.com/khiemns54/rebi"
  s.summary     = "Deploy rails app to Elastic Beanstalk."
  s.description = "Deploy rails app to Elastic Beanstalk via rake task with switchable ebextensions"
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  s.add_dependency "rubyzip", "~> 1.2.1"
  s.add_dependency "aws-sdk", "~> 2.10.2"
  s.add_dependency "dotenv", "~> 2.1.2"
  s.add_dependency "colorize", "~> 0.8.0"
  s.add_dependency "activesupport", "~> 5.0.2"
end
