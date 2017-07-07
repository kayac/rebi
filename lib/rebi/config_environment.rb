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
      get_opt ns[:autoscaling_launch], :InstanceType
    end

    def instance_num
      {
        min: get_opt(ns[:autoscaling_asg], :MinSize),
        max: get_opt(ns[:autoscaling_asg], :MaxSize)
      }
    end

    def key_name
      get_opt(ns[:autoscaling_launch], :EC2KeyName)
    end

    def service_role
      get_opt(ns[:eb_env], :ServiceRole)
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
      get_opt(ns(:app_env))
    end

    def get_opt namespace, opt_name=nil
      has_value_by_keys(option_settings, namespace, opt_name)
    end

    def get_raw_opt namespace, opt_name=nil
      has_value_by_keys(raw_conf[:option_settings], namespace, opt_name)
    end

    def opts_array opts=option_settings
      res = []
      opts.each do |namespace, v|
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

    def option_settings
      return @opt if @opt.present?
      opt = (cfg && cfg[:OptionSettings]) || {}.with_indifferent_access

      opt = opt.deep_merge(raw_conf[:option_settings] || {})

      ns.values.each do |ns|
        opt[ns] = {}.with_indifferent_access if opt[ns].blank?
      end

      opt = set_opt_env_var opt
      opt = set_opt_keyname opt
      opt = set_opt_instance_type opt
      opt = set_opt_instance_num opt
      opt = set_opt_service_role opt

      return @opt = opt
    end

    def ns key=nil
      key.present? ? NAMESPACE[key.to_sym] : NAMESPACE
    end

    private

    def has_value_by_keys(hash, *keys)
      if keys.empty? || hash.blank?
        return hash
      else
        return hash unless k = keys.shift
        return hash[k] && has_value_by_keys(hash[k], *keys)
      end
    end

    def set_opt_keyname opt
      k = if raw_conf.key?(:key_name)
        raw_conf[:key_name]
      elsif get_raw_opt(ns[:autoscaling_launch], :EC2KeyName)
        get_raw_opt(ns[:autoscaling_launch], :EC2KeyName)
      else
        nil
      end
      if k.present?
        opt[ns[:autoscaling_launch]].merge!({
          EC2KeyName: k
        }.with_indifferent_access)
      end
      return opt
    end

    def set_opt_service_role opt
      s_role = if raw_conf.key?(:service_role)
        raw_conf[:service_role]
      elsif role = get_raw_opt(ns[:eb_env], :ServiceRole)
        role
      else
        'aws-elasticbeanstalk-service-role'
      end
      if s_role.present?
        opt[ns[:eb_env]].merge!({
          ServiceRole: s_role,
        }.with_indifferent_access)
      end
      return opt
    end

    def set_opt_instance_type opt
      itype = raw_conf[:instance_type] \
              || get_raw_opt(ns[:autoscaling_launch], :InstanceType) \
              || "t2.small"
      if itype.present?
        opt[ns[:autoscaling_launch]].merge!({
          InstanceType: itype
        }.with_indifferent_access)
      end
      return opt
    end

    def set_opt_instance_num opt
      max = min = 1
      if raw_conf[:instance_num].present?
        min = raw_conf[:instance_num][:min]
        max = raw_conf[:instance_num][:min]
      elsif mi = get_raw_opt(ns[:autoscaling_asg], :MinSize) \
            || ma = get_raw_opt(ns[:autoscaling_asg], :MaxSize)
            min = mi if mi
            max = ma if ma
      end
      opt[ns[:autoscaling_asg]].merge!({
        MaxSize: max,
        MinSize: min,
      }.with_indifferent_access)
      return opt
    end

    def set_opt_env_var opt
      opt[ns[:app_env]].merge!(dotenv.merge(raw_environment_variables))
      return opt
    end

    def set_opt_default opt

      opt[ns[:healthreporting]].reverse_merge!({
        SystemType: 'enhanced',
      }.with_indifferent_access)

      opt[ns[:eb_command]].reverse_merge!({
        BatchSize: "50",
        BatchSizeType: "Percentage",
      }.with_indifferent_access)

      unless worker?
        opt[ns[:elb_policies]].reverse_merge!({
          ConnectionDrainingEnabled: true
        }.with_indifferent_access)

        opt[NAMESPACE[:elb_health]].reverse_merge!({
          Interval: 30
        }.with_indifferent_access)

        opt[NAMESPACE[:elb_loadbalancer]].reverse_merge!({
          CrossZone: true
        }.with_indifferent_access)
      end
      return opt
    end
  end
end
