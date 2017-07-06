module Rebi
  class ErbHelper
    def initialize input, env_vars
      @input = input
      @env = env_vars || {}
    end

    def rebi_env k=nil
      k.present? ? @env[k] : @env
    end

    def result
      ERB.new(@input).result(binding)
    end
  end
end
