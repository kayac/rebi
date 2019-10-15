module Rebi
  class Config
    include Singleton

    attr_accessor :data
    def initialize
      reload!
    end

    def config_file
      @config_file ||= "#{Rebi.root}/.rebi.yml"
    end

    def config_file=path
      @config_file = Pathname.new(path).realpath.to_s
    end

    attr_writer :aws_profile, :aws_key, :aws_secret, :region
    def aws_profile
      @aws_profile || data[:profile] || ENV["AWS_PROFILE"]
    end

    def aws_key
      data[:aws_key] || ENV["AWS_ACCESS_KEY_ID"]
    end

    def aws_secret
      data[:aws_secret] || ENV["AWS_SECRET_ACCESS_KEY"]
    end

    def aws_session_token
      ENV["AWS_SESSION_TOKEN"]
    end

    def region
      data[:region]
    end

    def reload!
      @data = nil
      set_aws_config
      return data
    end

    def app_name
      data[:app_name]
    end

    def app_name=name
      data[:app_name] = name
    end

    def app_description
      data[:app_description] || "Created via rebi"
    end

    def stage stage
      data[:stages] && data[:stages][stage] || raise(Rebi::Error::ConfigNotFound.new("Stage: #{stage}"))
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

    def data
      return @data unless @data.nil?
      begin
        @data = YAML::load(ERB.new(IO.read(config_file)).result).with_indifferent_access
      rescue Errno::ENOENT
        @data = {}.with_indifferent_access
      end
      return @data
    end

    def push_to_file
      File.open(config_file, "wb") do |f|
        f.write JSON.parse(data.to_json).to_yaml
      end

      Rebi.log "Saved config to #{config_file}"
      Rebi.log "For more configs, please refer sample or github"
    end

    private
    def set_aws_config
      conf = {}

      if region
        conf.merge!({
          region: region
          })
      end

      if aws_profile
        conf.merge!({
          profile: aws_profile
          })
      elsif aws_secret && aws_key
        conf.merge!(
          credentials: Aws::Credentials::new(aws_key, aws_secret, aws_session_token)
        )
      end

      Aws.config.update conf
    end
  end
end
