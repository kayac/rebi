module Rebi
  class Config
    include Singleton

    def config_file
      @config_file ||= "#{Rebi.root}/config/rebi.yml"
    end

    def config_file=path
      @config_file = Pathname.new(path).realpath.to_s
    end

    def reload!
      @data = nil
      return data
    end

    def app_name
      data[:app_name]
    end

    def app_description
      data[:app_description] || "Created via rebi"
    end

    def stage stage
      data[:stages][stage] || raise(Rebi::Error::ConfigNotFound.new("Stage: #{stage}"))
    end

    def timeout
      (data[:timeout] || 60*10).second
    end

    def environment stg_name, env_name
      stg = stage stg_name
      raise(Rebi::Error::ConfigNotFound.new("Environment config: #{env_name}")) unless stg.key?(env_name)
      return Rebi::ConfigEnvironment.new(stg_name, env_name, stg[env_name] || {})
    end

    def env_by_name name
      data[:stages].each do |stg_name, stg_conf|
        stg = stage stg_name
        stg_conf.keys.each do |env_name|
          env_conf = Rebi::ConfigEnvironment.new(stg_name, env_name, stg[env_name] || {})
          return env_conf if env_conf.name == name
        end
      end
      return nil
    end

    def stages
      data[:stages].keys
    end

    private
    def data
      @data ||= YAML::load(ERB.new(IO.read(config_file)).result).with_indifferent_access
      raise Rebi::Error::ConfigInvalid.new("app_name cannot be nil") if @data[:app_name].blank?
      raise Rebi::Error::ConfigInvalid.new("stages cannot be nil") if @data[:stages].blank?
      return @data
    end
  end
end
