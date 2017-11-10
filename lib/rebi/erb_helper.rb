module Rebi
  class ErbHelper
    def initialize input, env_conf
      @input = input
      @env = env_conf.environment_variables || {}
      @options = env_conf.options
    end

    def rebi_env k=nil
      k.present? ? @env[k] : @env
    end

    def rebi
      OpenStruct.new ({
        env: @env,
        opts: @options,
        options: @options,
        })
    end

    def result
      ERB.new(@input).result(binding)
    end
  end
end
