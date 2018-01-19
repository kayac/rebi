module Rebi
  class Application
    include Rebi::Log
    attr_reader :app, :app_name, :client, :s3_client
    def initialize app, client=Rebi.eb
      @app = app
      @app_name = app.application_name
      @client = client
    end

    def bucket_name
      @bucket_name ||= client.create_storage_location.s3_bucket
    end

    def environments
      Rebi::Environment.all app_name
    end

    def log_label
      app_name
    end

    def deploy stage_name, env_name=nil, opts={}
      return deploy_stage(stage_name, opts) if env_name.blank?
      env = get_environment stage_name, env_name
      begin
        env.deploy opts
      rescue Interrupt
        log("Interrupt")
      end
    end

    def deploy_stage stage_name, opts={}
      threads = []
      Rebi.config.stage(stage_name).each do |env_name, conf|
        next if conf.blank?
        threads << Thread.new do
          begin
            deploy stage_name, env_name, opts
          rescue Exception => e
            error(e.message)
            opts[:trace] && e.backtrace.each do |m|
              error(m)
            end
          end
        end
      end

      ThreadsWait.all_waits(*threads)
    end

    def print_environment_variables stage_name, env_name, from_config=false
      if env_name.blank?
        Rebi.config.stage(stage_name).each do |e_name, conf|
          next if conf.blank?
          print_environment_variables stage_name, e_name, from_config
        end
        return
      end

      env = get_environment stage_name, env_name
      env_vars = from_config ? env.config.environment_variables : env.environment_variables

      log("#{from_config ? "Config" : "Current"} environment variables")
      env_vars.each do |k,v|
        log("#{k}=#{v}")
      end
      log("--------------------------------------")
    end

    def print_environment_status stage_name, env_name
      if env_name.blank?
        Rebi.config.stage(stage_name).each do |e_name, conf|
          next if conf.blank?
          print_environment_status stage_name, e_name
        end
        return
      end

      env = get_environment stage_name, env_name
      env.check_created!
      log("--------- CURRENT STATUS -------------")
      log("id: #{env.id}")
      log("Status: #{env.status}")
      log("Health: #{env.health}")
      log("--------------------------------------")
    end

    def terminate! stage_name, env_name
      env = get_environment stage_name, env_name
      begin
        req_id = env.terminate!
        ThreadsWait.all_waits(env.watch_request req_id) if req_id
      rescue Rebi::Error::EnvironmentInUpdating => e
        log("Environment in updating")
        raise e
      end
    end

    def print_list
      others = []
      configed = Hash.new {|h, k| h[k] = {} }
      environments.each do |e|
        if env_conf = Rebi.config.env_by_name(e.environment_name)
          configed[env_conf.stage.to_s].merge! env_conf.env_name.to_s => env_conf.name
        else
          others << e.environment_name
        end
      end

      configed.each do |stg, envs|
        log h1("#{stg.camelize}")
        envs.each do |kname, env_name|
          env = get_environment stg, kname
          log "\t[#{kname.camelize}] #{env.name} #{h2(env.status)} #{hstatus(env.health)}"
        end
      end

      if others.present?
        log h1("Others")
        others.each do |e|
          log "\t- #{e}"
        end
      end
    end

    def ssh_interaction stage_name, env_name, opts={}
      env_name = Rebi.config.stage(stage_name).keys.first unless env_name
      env = get_environment stage_name, env_name
      instance_ids = env.instance_ids
      return if instance_ids.empty?

      instance_ids.each.with_index do |i,idx|
        log "#{idx+1}) #{i}"
      end

      instance_id = instance_ids.first

      if instance_ids.count != 1 && opts[:select]

        idx = 0
        while idx < 1 || idx > instance_ids.count
          idx = ask_for_integer "Select an instance to ssh into:"
        end
        instance_id = instance_ids[idx - 1]
      end

      log "Preparing to ssh into [#{instance_id}]"
      env.ssh instance_id
    end

    def get_environment stage_name, env_name
      Rebi::Environment.new stage_name, env_name, client
    end

    def self.client
      Rebi.eb
    end

    def self.get_application app_name
      raise Error::ApplicationNotFound.new unless app = client.describe_applications(application_names: [app_name]).applications.first
      return Rebi::Application.new(app, client)
    end

    def self.create_application app_name, description=nil
      res = client.create_application(
        application_name: app_name,
        description: description,
      )
      return Rebi::Application.new(res.application, client)
    end

    def self.get_or_create_application app_name
      begin
        return get_application app_name
      rescue Error::ApplicationNotFound
        return create_application app_name, Rebi.config.app_description
      end
    end

  end
end
