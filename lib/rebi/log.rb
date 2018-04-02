module Rebi
  module Log
    def log mes, label=self.log_label
        puts "#{label.present? ? "#{colorize_prefix(label)}: " : ""}#{mes}"
    end

    def error mes, label=self.error_label
      puts colorize(label, color: :white, background: :red) + ": " + mes
    end

    def log_label
      "Rebi"
    end

    def error_label
      "ERROR"
    end

    def colorize_prefix(prefix)
      colors = ColorizedString.colors
      colors.delete :light_black
      h = prefix.chars.inject(0) do |m, c|
        m + c.ord
      end
      return colorize(prefix, color: colors[h % colors.count], background: :light_black)
    end

    def h1 s
      colorize(s, color: :light_yellow, background: :light_blue)
    end

    def h2 s
      colorize(s, color: :light_blue, background: :light_cyan)
    end

    def h3 s
      colorize(s, color: :light_yellow, background: :light_blue, mode: :bold)
    end

    def h4 s
      colorize(s, color: :black, background: :green, mode: :italic)
    end

    def hstatus s
      bg = s.downcase.to_sym
      bg = :light_black unless ColorizedString.colors.include?(bg)
      colorize(s, color: :black, background: bg, mode: :italic)
    end

    def colorize mes, opts={}
      ColorizedString[mes].colorize(opts)
    end
  end
end
