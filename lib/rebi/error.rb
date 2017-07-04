module Rebi
  class Error < StandardError
    ApplicationNotFound = Class.new(self)
    EnvironmentExisted = Class.new(self)
    EnvironmentNotExisted = Class.new(self)
    ConfigFileNotFound = Class.new(self)
    ConfigNotFound = Class.new(self)
    ConfigInvalid = Class.new(self)
    NoGit = Class.new(self)
    ServiceError = Class.new(self)
    EnvironmentInUpdating = Class.new(self)
  end
end
