module Rebi
  class Environment

    attr_reader :stage_name,
                :env_name,
                :app_name,
                :name,
                :config

    attr_accessor :client,
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

    def initialize stage_name, env_name, client=Rebi.client
      @stage_name = stage_name
      @env_name = env_name
      @client = client
      @config = Rebi.config.environment(stage_name, env_name)
      @app_name = @config.app_name
      @api_data
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
      thread.join
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

    def init version_label, opts={}
      log("Creating new environment")
      start_time = Time.now
      self.api_data = client.create_environment({
        application_name: config.app_name,
        cname_prefix: config.cname_prefix,
        environment_name: config.name,
        version_label: version_label,
        tier: config.tier,
        description: config.description,
        option_settings: config.opts_array,
      }.merge(if(config.platform_arn)
        { platform_arn: config.platform_arn}
      else
        { solution_stack_name: config.solution_stack_name}
      end))
      request_id = events(start_time).select do |e|
        e.message.match(response_msgs('event.createstarting'))
      end.map(&:request_id).first
      return request_id
    end

    def update version_label, opts={}
      raise Rebi::Error::EnvironmentInUpdating.new(name) if in_updating?
      log("Start updating")
      start_time = Time.now
      deploy_opts = gen_deploy_opts
      deploy_args = {
        application_name: config.app_name,
        environment_name: config.name,
        version_label: version_label,
        description: config.description,
        option_settings: deploy_opts[:option_settings],
        options_to_remove: deploy_opts[:options_to_remove],
      }

      if opts[:source_only]
        deploy_args.delete(:option_settings)
        deploy_args.delete(:options_to_remove)
      elsif opts[:settings_only]
        deploy_args.delete(:version_label)
      end

      self.api_data = client.update_environment(deploy_args)

      request_id = events(start_time).select do |e|
        e.message.match(response_msgs('event.updatestarting'))
      end.map(&:request_id).first

      return request_id
    end

    def deploy version_label, opts={}
      request_id = if created?
        update version_label, opts
      else
        init version_label, opts
      end
      return request_id
    end

    def terminate!
      check_created
      log("Start terminating")
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

    def log mes
      Rebi.log(mes, name)
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

    def gen_deploy_opts
      to_deploy = []
      to_remove = []
      config.opts_array.each do |o|
        o = o.deep_dup
        if o[:namespace] == config.ns(:app_env) && o[:value].blank?
          o.delete(:value)
          to_remove << o
          next
        end
        to_deploy << o
      end
      return {
        option_settings: to_deploy,
        options_to_remove:  to_remove,
      }
    end

    def self.create stage_name, env_name, version_label, client
      env =  new stage_name, env_name, client
      raise Rebi::Error::EnvironmentExisted.new if env.created?

      env.init version_label
      return env
    end

    # TODO
    def self.all client=Rebi.client
      client.describe_environments(application_name: app_name,
                                   include_deleted: false).environments
    end

    def self.get stage_name, env_name, client=Rebi.client
      env = new stage_name, env_name, client
      return env.created? ? env : nil
    end

  end
end
