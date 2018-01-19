module Rebi
  class Environment

    include Rebi::Log

    attr_reader :stage_name,
                :env_name,
                :app_name,
                :name,
                :config

    attr_accessor :client,
                  :s3_client,
                  :api_data


    RESPONSES = {
        'event.createstarting': 'createEnvironment is starting.',
        'event.terminatestarting': 'terminateEnvironment is starting.',
        'event.updatestarting': 'Environment update is starting.',
        'event.redmessage': 'Environment health has been set to RED',
        'event.commandfailed': 'Command failed on instance',
        'event.launchfailed': 'Failed to launch',
        'event.deployfailed': 'Failed to deploy application.',
        'event.redtoyellowmessage': 'Environment health has transitioned from YELLOW to RED',
        'event.yellowmessage': 'Environment health has been set to YELLOW',
        'event.greenmessage': 'Environment health has been set to GREEN',
        'event.launchsuccess': 'Successfully launched environment:',
        'event.launchbad': 'Create environment operation is complete, but with errors',
        'event.updatebad': 'Update environment operation is complete, but with errors.',
        'git.norepository': 'Error: Not a git repository (or any of the parent directories): .git',
        'env.updatesuccess': 'Environment update completed successfully.',
        'env.cnamenotavailable': 'DNS name \([^ ]+\) is not available.',
        'env.nameexists': 'Environment [^ ]+ already exists.',
        'app.deletesuccess': 'The application has been deleted successfully.',
        'app.exists': 'Application {app-name} already exists.',
        'app.notexists': 'No Application named {app-name} found.',
        'logs.pulled': 'Pulled logs for environment instances.',
        'logs.successtail': 'Successfully finished tailing',
        'logs.successbundle': 'Successfully finished bundling',
        'env.terminated': 'terminateEnvironment completed successfully.',
        'env.invalidstate': 'Environment named {env-name} is in an invalid state for this operation. Must be Ready.',
        'loadbalancer.notfound': 'There is no ACTIVE Load Balancer named',
        'ec2.sshalreadyopen': 'the specified rule "peer: 0.0.0.0/0, TCP, from port: 22, to port: 22,',
    }

    def initialize stage_name, env_name, client=Rebi.eb
      @stage_name = stage_name
      @env_name = env_name
      @client = client
      @s3_client = Rebi.s3
      @config = Rebi.config.environment(stage_name, env_name)
      @app_name = @config.app_name
      @api_data
    end

    def bucket_name
      @bucket_name ||= client.create_storage_location.s3_bucket
    end

    def name
      created? ? api_data.environment_name : config.name
    end

    def cname
      created? ? api_data.cname : nil
    end

    def version_label
      created? ? api_data.version_label : nil
    end

    def id
      created? ? api_data.environment_id : nil
    end

    def status
      check_created! && api_data.status
    end

    def in_updating?
      !!status.match("ing$")
    end

    def health
      check_created! && api_data.health
    end

    def option_settings
      check_created!
      client.describe_configuration_settings({
        application_name: app_name,
        environment_name: name
      }).configuration_settings.first.option_settings.map do |o|
        {
          namespace: o.namespace,
          value: o.value,
          resource_name: o.resource_name,
          option_name: o.option_name,
        }.with_indifferent_access
      end
    end

    def environment_variables
      option_settings.select do |o|
          o[:namespace] == config.ns(:app_env)
      end.map do |o|
            [o[:option_name], o[:value]]
      end.to_h.with_indifferent_access
    end

    def check_created
      raise Rebi::Error::EnvironmentNotExisted.new("#{name} not exists") unless created?
      return created?
    end

    # refresh data
    def check_created!
      refresh
      check_created
    end

    def created?
      !!api_data
    end

    def api_data
      @api_data ||= client.describe_environments(application_name: config.app_name,
                                                 environment_names:[config.name],
                                                 include_deleted: false).environments.first
    end

    def response_msgs key=nil
      @response_msgs ||= RESPONSES.with_indifferent_access
      return key ? @response_msgs[key] : @response_msgs
    end

    def watch_request request_id
      return unless request_id
      log h1("WATCHING REQUEST [#{request_id}]")
      check_created!
      start = Time.now
      finished = false
      last_time = Time.now - 30.minute
      thread = Thread.new do
        while (start + Rebi.config.timeout) > Time.now && !finished
          events(last_time, request_id).reverse.each do |e|
            finished ||= success_message?(e.message)
            last_time = [last_time + 1.second, e.event_date + 1.second].max
            log(e.message)
          end
          sleep(5) unless finished
        end
        log ("Timeout") unless finished
      end
      begin
        thread.join
      rescue Interrupt
        log("Interrupt")
      end
      return thread
    end

    def events start_time=Time.now, request_id=nil
      client.describe_events({
        application_name: app_name,
        environment_name: name,
        start_time: start_time,
      }.merge( request_id ? {request_id: request_id} : {})).events
    end

    def refresh
      self.api_data = nil
      return self
    end

    def instance_ids
      resp = client.describe_environment_resources environment_name: self.name
      resp.environment_resources.instances.map(&:id).sort
    end

    def create_app_version opts={}
      return if opts[:settings_only]
      start = Time.now.utc
      source_bundle = Rebi::ZipHelper.new.gen(self.config, opts)
      version_label = source_bundle[:label]
      key = "#{app_name}/#{version_label}.zip"
      log("Uploading source bundle: #{version_label}.zip")
      s3_client.put_object(
        bucket: bucket_name,
        key: key,
        body: source_bundle[:file].read
        )
      log("Creating app version: #{version_label}")
      client.create_application_version({
        application_name: app_name,
        description: source_bundle[:message],
        version_label: version_label,
        source_bundle: {
          s3_bucket: bucket_name,
          s3_key: key
          }
        })
      log("App version was created in: #{Time.now.utc - start}s")
      return version_label
    end

    def init version_label, opts={}
      log h2("Start creating new environment")
      start_time = Time.now

      self.check_instance_profile

      self.api_data = client.create_environment _create_args(version_label, opts)

      request_id = events(start_time).select do |e|
        e.message.match(response_msgs('event.createstarting'))
      end.map(&:request_id).first
      return request_id
    end

    def update version_label, opts={}

      raise Rebi::Error::EnvironmentInUpdating.new("Environment is in updating: #{name}") if in_updating?
      log h2("Start updating")
      start_time = Time.now

      self.api_data = client.update_environment(_update_args(version_label, opts))

      request_id = events(start_time).select do |e|
        e.message.match(response_msgs('event.updatestarting'))
      end.map(&:request_id).first

      return request_id
    end

    def deploy opts={}
      _run_hooks :pre
      version_label = create_app_version opts
      request_id = if created?
        update version_label, opts
      else
        init version_label, opts
      end
      log h3("DEPLOYING")
      _run_hooks :post
      watch_request request_id
      return request_id
    end

    def terminate!
      check_created
      log h2("Start terminating")
      client.terminate_environment({
        environment_name: name,
        environment_id: id,
        })
      start_time = Time.now

      request_id = events(start_time).select do |e|
        e.message.match(response_msgs('event.updatestarting'))
      end.map(&:request_id).first
      return request_id
    end

    def log_label
      name
    end

    def success_message? mes
      return true if [
        'event.greenmessage',
        'event.launchsuccess',
        'logs.pulled',
        'env.terminated',
        'env.updatesuccess',
        'app.deletesuccess',
      ].map{|k| response_msgs(k)}.any?{|s| mes.match(s)}

      if [
            'event.redmessage',
            'event.launchbad',
            'event.updatebad',
            'event.commandfailed',
            'event.launchfailed',
            'event.deployfailed',
          ].map {|k| response_msgs(k)}.any? {|s| mes.match(s)}
        raise Rebi::Error::ServiceError.new(mes)
      end

      return false
    end

    def ssh instance_id
      raise "Invalid instance_id" unless self.instance_ids.include?(instance_id)


      instance  = Rebi.ec2.describe_instance instance_id

      raise Rebi::Error::EC2NoKey.new unless instance.key_name.present?
      raise Rebi::Error::EC2NoIP.new unless instance.public_ip_address.present?


      Rebi.ec2.authorize_ssh instance_id do
        user = "ec2-user"
        key_file = "~/.ssh/#{instance.key_name}.pem"
        raise Rebi::Error::KeyFileNotFound unless File.exists? File.expand_path(key_file)
        cmd = "ssh -i #{key_file} #{user}@#{instance.public_ip_address}"
        log cmd

        begin
          Subprocess.check_call(['ssh', '-i', key_file,  "#{user}@#{instance.public_ip_address}"])
        rescue Subprocess::NonZeroExit => e
          log e.message
        end

      end

    end

    def check_instance_profile
      iam = Rebi.iam
      begin
        iam.get_instance_profile({
          instance_profile_name: config.instance_profile
          })
        return true
      rescue Aws::IAM::Errors::NoSuchEntity => e
        raise e unless config.default_instance_profile?
        self.create_defaut_profile
      end
    end

    def create_defaut_profile
      iam = Rebi.iam
      profile = role = Rebi::ConfigEnvironment::DEFAULT_IAM_INSTANCE_PROFILE
      iam.create_instance_profile({
        instance_profile_name: profile
        })

      document = <<-JSON
{
  "Version":"2008-10-17",
  "Statement":[
      {
        "Effect":"Allow",
        "Principal":{
          "Service":["ec2.amazonaws.com"]
        },
        "Action":["sts:AssumeRole"]
      }
  ]
}
      JSON
      begin
        iam.create_role({
          role_name: role,
          assume_role_policy_document: document
          })
      rescue Aws::IAM::Errors::EntityAlreadyExists
      end

      iam.add_role_to_instance_profile({
        instance_profile_name: profile,
        role_name: role
        })

    end

    def self.create stage_name, env_name, version_label, client
      env =  new stage_name, env_name, client
      raise Rebi::Error::EnvironmentExisted.new if env.created?

      env.init version_label
      return env
    end

    # TODO
    def self.all app_name, client=Rebi.eb
      client.describe_environments(application_name: app_name,
                                   include_deleted: false).environments
    end

    def self.get stage_name, env_name, client=Rebi.eb
      env = new stage_name, env_name, client
      return env.created? ? env : nil
    end

    private

    def _create_args version_label, opts={}
      args = {
          application_name: config.app_name,
          environment_name: config.name,
          version_label: version_label,
          tier: config.tier,
          description: config.description,
          option_settings: config.opts_array,
        }

      args.merge!(cname_prefix: config.cname_prefix) if config.cname_prefix

      args.merge!(config.platform_arn ? { platform_arn: config.platform_arn } : { solution_stack_name: config.solution_stack_name })
      return args
    end

    def _update_args version_label, opts={}
      deploy_opts = _gen_deploy_opts

      args = {
        application_name: config.app_name,
        environment_name: config.name,
        description: config.description,
      }

      args.merge!(version_label: version_label) if version_label

      if opts[:include_settings] || opts[:settings_only]
        args.merge!({
          option_settings: deploy_opts[:option_settings],
          options_to_remove: deploy_opts[:options_to_remove],
        })
        args.delete(:version_label) if opts[:settings_only]
      else
        args.merge!({
          option_settings: deploy_opts[:env_only],
          options_to_remove: deploy_opts[:options_to_remove],
        })
      end

      return args
    end

    def _gen_deploy_opts
      to_deploy = []
      to_remove = []
      env_only = []
      config.opts_array.each do |o|
        o = o.deep_dup

        if o[:namespace] == config.ns(:app_env)
          if o[:value].blank?
            o.delete(:value)
            to_remove << o
            next
          else
            env_only << o
          end
        end
        to_deploy << o
      end
      return {
        option_settings: to_deploy,
        options_to_remove:  to_remove,
        env_only: env_only,
      }
    end

    def _run_hooks type
      if hooks = config.hooks[type]
        log h1("RUNNING #{type.upcase} HOOKS")
        hooks.each do |cmd|
          log h4(cmd)
          system "#{cmd} 2>&1"
          raise "Command failed" unless $?.success?
        end
        log h1("#{type.upcase} HOOKS FINISHED!!!")
      end
    end
  end
end
