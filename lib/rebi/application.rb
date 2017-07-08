module Rebi
  class Application
    attr_reader :app, :app_name, :client, :s3_client
    def initialize app, client
      @app = app
      @app_name = app.application_name
      @client = client
      @s3_client = Aws::S3::Client.new
    end

    def bucket_name
      @bucket_name ||= client.create_storage_location.s3_bucket
    end

    def environments
      Rebi::Environment.all app_name
    end

    def deploy stage_name, env_name=nil, opts={}
      return deploy_stage(stage_name, opts) if env_name.blank?
      env = Rebi::Environment.new stage_name, env_name, client
      app_version = create_app_version env
      begin
        req_id = env.deploy app_version, opts
        env.watch_request req_id if req_id
      rescue Rebi::Error::EnvironmentInUpdating => e
        Rebi.log("Environment in updating", env.name)
        raise e
      end
      req_id
    end

    def deploy_stage stage_name, opts={}
      threads = []
      Rebi.config.stage(stage_name).each do |env_name, conf|
        next if conf.blank?
        threads << Thread.new do
          begin
            deploy stage_name, env_name, opts
          rescue Exception => e
            Rebi.log(e.message, "ERROR")
            e.backtrace.each do |m|
              Rebi.log(m, "ERROR")
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

      env = Rebi::Environment.new stage_name, env_name, client
      env_vars = from_config ? env.config.environment_variables : env.environment_variables

      Rebi.log("#{from_config ? "Config" : "Current"} environment variables", env.name)
      env_vars.each do |k,v|
        Rebi.log("#{k}=#{v}")
      end
      Rebi.log("--------------------------------------", env.name)
    end

    def print_environment_status stage_name, env_name
      if env_name.blank?
        Rebi.config.stage(stage_name).each do |e_name, conf|
          next if conf.blank?
          print_environment_status stage_name, e_name
        end
        return
      end

      env = Rebi::Environment.new stage_name, env_name, client
      env.check_created!
      Rebi.log("--------- CURRENT STATUS -------------", env.name)
      Rebi.log("id: #{env.id}", env.name)
      Rebi.log("Status: #{env.status}", env.name)
      Rebi.log("Health: #{env.health}", env.name)
      Rebi.log("--------------------------------------", env.name)
    end

    def terminate! stage_name, env_name
      env = Rebi::Environment.new stage_name, env_name, client
      begin
        req_id = env.terminate!
        ThreadsWait.all_waits(env.watch_request req_id) if req_id
      rescue Rebi::Error::EnvironmentInUpdating => e
        Rebi.log("Environment in updating", env.name)
        raise e
      end
    end

    def create_app_version env
      start = Time.now.utc
      source_bundle = Rebi::ZipHelper.new.gen(env.config)
      version_label = source_bundle[:label]
      key = "#{app_name}/#{version_label}.zip"
      Rebi.log("Uploading source bundle: #{version_label}.zip", env.config.name)
      s3_client.put_object(
        bucket: bucket_name,
        key: key,
        body: source_bundle[:file].read
        )
      Rebi.log("Creating app version: #{version_label}", env.config.name)
      client.create_application_version({
        application_name: app_name,
        description: source_bundle[:message],
        version_label: version_label,
        source_bundle: {
          s3_bucket: bucket_name,
          s3_key: key
          }
        })
      Rebi.log("App version was created in: #{Time.now.utc - start}s", env.config.name)
      return version_label
    end


    def self.client
      Rebi.client || Aws::ElasticBeanstalk::Client.new
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