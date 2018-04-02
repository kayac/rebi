module Rebi

  class InitService

    include Rebi::Log

    attr_reader :stage_name, :env_name, :stage, :env_data

    def initialize stage_name, env_name
      if config.app_name.blank?
        config.app_name = get_appname
      end
      @stage_name = stage_name
      @env_name = env_name
      config.data[:stages] ||= {}.with_indifferent_access

      begin
        @stage = config.stage stage_name
        raise "Already exists" if @stage.keys.include? env_name
      rescue Rebi::Error::ConfigNotFound
        config.data[:stages][stage_name] = {}.with_indifferent_access
      end

      config.data[:stages][stage_name].merge!({
        env_name => ConfigEnvironment::DEFAULT_CONFIG.clone
      }.with_indifferent_access)

      @env_data = config.data[:stages][stage_name][env_name]
    end

    def config
      Rebi.config
    end

    def eb
      @eb ||= Rebi.eb
    end

    def execute
      env_data.reverse_merge!({name: get_envname})
      env_data[:solution_stack_name] = get_solution_stack
      config.push_to_file
    end

    def get_appname
      app_name = nil
      if (apps = eb.applications).present?
        idx = -1
        while idx < 0 || idx > apps.count
          apps.each.with_index do |app, idx|
            log "#{idx + 1}: #{app}"
          end
          log "0: Create new application"
          idx = ask_for_integer "Select application:"
        end
        app_name = idx > 0 ? apps[idx - 1] : nil
      end

      if app_name.blank?
        app_name = ask_for_string "Enter application name:"
      end

      app_name
    end

    def get_envname
      name = ask_for_string "Enter environment name(Default: #{default_envname}):"
      name = name.chomp.gsub(/\s+/, "")

      name = name.present? ? name : default_envname
      name
    end

    def default_envname
      "#{env_name}-#{stage_name}"
    end

    def get_solution_stack
      idx = 0
      platform = nil
      version = nil
      while idx <= 0 || idx > eb.platforms.count
        eb.platforms.each.with_index do |pl, idx|
          log "#{idx + 1}: #{pl}"
        end
        idx = ask_for_integer "Select platform:"
      end

      platform = eb.platforms[idx - 1]
      versions = eb.versions_by_platform platform
      idx = versions.count <= 1 ? 1 : 0

      while idx <=0 || idx > versions.count
        versions.each.with_index do |ver, idx|
          log "#{idx + 1}: #{ver}"
        end
        idx = ask_for_integer "Select version:"
      end

      version = versions[idx - 1]

      eb.get_solution_stack platform, version
    end

    def log_label
      ""
    end
  end
end
