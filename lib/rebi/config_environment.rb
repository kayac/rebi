require 'pathname'

module Rebi
  class ConfigEnvironment

    attr_reader :stage,
                :env_name,
                :name,
                :description,
                :cname_prefix,
                :tier,
                :instance_type,
                :instance_num,
                :key_name,
                :service_role,
                :ebextensions,
                :solution_stack_name,
                :cfg_file,
                :env_file,
                :environment_variables,
                :option_settings,
                :raw_conf

    NAMESPACE ={
      app_env: "aws:elasticbeanstalk:application:environment",
      eb_env: "aws:elasticbeanstalk:environment",
      autoscaling_launch: "aws:autoscaling:launchconfiguration",
      autoscaling_asg: "aws:autoscaling:asg",
      elb_policies: "aws:elb:policies",
      elb_health: "aws:elb:healthcheck",
      elb_loadbalancer: "aws:elb:loadbalancer",
      healthreporting: "aws:elasticbeanstalk:healthreporting:system",
      eb_command: "aws:elasticbeanstalk:command",
    }

    UPDATEABLE_NS = {
      autoscaling_asg: [:MaxSize, :MinSize],
      autoscaling_launch: [:InstanceType, :EC2KeyName],
      eb_env: [:ServiceRole],
    }

    def initialize stage, env_name, env_conf={}
      @raw_conf = env_conf.with_indifferent_access
      @stage = stage.to_sym
      @env_name = env_name.to_sym
    end

    def name
      @name ||= raw_conf[:name] || "#{env_name}-#{stage}"
    end

    def app_name
      Rebi.config.app_name
    end

    def description
      @description ||= raw_conf[:description] || "Created via rebi"
    end

    def cname_prefix
      @cname_prefix ||= raw_conf[:cname_prefix] || "#{name}-#{stage}"
    end

    def tier
      return @tier if @tier
      t = if raw_conf[:tier]
        raw_conf[:tier].to_sym
      elsif cfg.present? && cfg[:EnvironmentTier].present? && cfg[:EnvironmentTier][:Name].present?
        cfg[:EnvironmentTier][:Name] == "Worker" ? :worker : :web
      else
        :web
      end

      @tier = if t == :web
        {
          name: "WebServer",
          type: "Standard",
        }
      elsif t == :worker
        {
          name: "Worker",
          type: "SQS/HTTP",
        }
      else
        Rebi::Error::ConfigInvalid.new("Invalid tier")
      end

      return @tier = @tier.with_indifferent_access
    end

    def worker?
      tier[:name] == "Worker" ? true : false
    end

    def instance_type
      @instance_type ||= raw_conf[:instance_type] || "t2.small"
    end

    def instance_num
      return @instance_num  if @instance_num
      @instance_num = {
        min: 1,
        max: 1,
      }.with_indifferent_access

      if instance_num = raw_conf[:instance_num]
        if (min = instance_num[:min]) && (max = instance_num[:max]) && (min > 0) && (max >= min)
          @instance_num[:min] = min
          @instance_num[:max] = max
        else
          raise Rebi::Error::ConfigInvalid.new("instance_num")
        end
      end

      return @instance_num
    end

    def key_name
      @key_name ||= raw_conf[:key_name]
    end

    def service_role
      raw_conf.key?(:service_role) ? raw_conf[:service_role] : 'aws-elasticbeanstalk-service-role'
    end

    def cfg_file
      @cfg_file ||= raw_conf[:cfg_file]
      return @cfg_file if @cfg_file.blank?
      return @cfg_file if Pathname.new(@cfg_file).absolute?
      @cfg_file = ".elasticbeanstalk/saved_configs/#{@cfg_file}.cfg.yml" unless @cfg_file.match(".yml$")
      return (@cfg_file = "#{Rebi.root}/#{@cfg_file}")
    end

    def env_file
      @env_file ||= raw_conf[:env_file]
    end

    def cfg
      begin
        return nil if cfg_file.blank?
        return (@cfg ||= YAML.load(ERB.new(IO.read(cfg_file)).result).with_indifferent_access)
      rescue Errno::ENOENT
        raise Rebi::Error::ConfigInvalid.new("cfg_file: #{cfg_file}")
      end
    end

    def solution_stack_name
      @solution_stack_name ||= raw_conf[:solution_stack_name] || "64bit Amazon Linux 2017.03 v2.4.1 running Ruby 2.3 (Puma)"
    end

    def platform_arn
      cfg && cfg[:Platform] && cfg[:Platform][:PlatformArn]
    end

    def ebextensions
      return @ebextensions ||= if (ebx = raw_conf[:ebextensions])
        ebx = [ebx] if ebx.is_a?(String)
        ebx.prepend(".ebextensions") unless ebx.include?(".ebextensions")
        ebx
      else
        [".ebextensions"]
      end
    end

    def raw_environment_variables
      raw_conf[:environment_variables] || {}
    end

    def dotenv
      env_file.present? ? Dotenv.load(env_file).with_indifferent_access : {}
    end

    def environment_variables
      option_settings.select do |o|
        o[:namespace] == NAMESPACE[:app_env]
      end.map do |o|
          [o[:option_name], o[:value]]
      end.to_h.with_indifferent_access
    end

    def env_var_for_erb
      OpenStruct.new(REBI_ENV: environment_variables)
    end

    def option_settings
      opt = (cfg && cfg[:OptionSettings]) || {}.with_indifferent_access

      NAMESPACE.values.each do |ns|
        opt[ns] = {}.with_indifferent_access if opt[ns].blank?
      end

      opt[NAMESPACE[:app_env]].merge!(dotenv.merge(raw_environment_variables)).compact!

      opt[NAMESPACE[:healthreporting]].reverse_merge!({
        SystemType: 'enhanced',
      }.with_indifferent_access)

      opt[NAMESPACE[:eb_command]].reverse_merge!({
        BatchSize: "50",
        BatchSizeType: "Percentage",
      }.with_indifferent_access)

      if key_name.present?
        opt[NAMESPACE[:autoscaling_launch]].merge!({
          EC2KeyName: key_name
        }.with_indifferent_access)
      end

      if service_role.present?
        opt[NAMESPACE[:eb_env]].merge!({
          ServiceRole: service_role
        }.with_indifferent_access)
      end

      if instance_type.present?
        opt[NAMESPACE[:autoscaling_launch]].merge!({
          InstanceType: instance_type
        }.with_indifferent_access)
      end

      if instance_num.present?
        opt[NAMESPACE[:autoscaling_asg]].merge!({
          MaxSize: instance_num[:max],
          MinSize: instance_num[:min],
        }.with_indifferent_access)
      end

      unless worker?
        opt[NAMESPACE[:elb_policies]].reverse_merge!({
          ConnectionDrainingEnabled: true
        }.with_indifferent_access)

        opt[NAMESPACE[:elb_health]].reverse_merge!({
          Interval: 30
        }.with_indifferent_access)

        opt[NAMESPACE[:elb_loadbalancer]].reverse_merge!({
          CrossZone: true
        }.with_indifferent_access)
      end

      res = []
      opt.each do |namespace, v|
        namespace, resource_name = namespace.split(".").reverse
        v.each do |option_name, value|
          res << {
            resource_name: resource_name,
            namespace: namespace,
            option_name: option_name,
            value: value.to_s,
          }.with_indifferent_access
        end
      end
      return res
    end

    def diff_options opts

    end
  end
end
