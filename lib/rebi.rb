require 'active_support/all'
require 'aws-sdk'
require 'colorized_string'
require 'singleton'
require 'yaml'
require 'dotenv'
require 'tempfile'
require 'pathname'
require 'zip'
require 'fileutils'
require 'erb'
require 'ostruct'

require 'rebi/application'
require 'rebi/environment'
require 'rebi/config'
require 'rebi/config_environment'
require 'rebi/error'
require 'rebi/zip_helper'

Dotenv.load

module Rebi
  extend self
  attr_accessor :config_file
  @config_file = "config/rebi.yml"

  def root
    Dir.pwd
  end

  def client c=nil
    @@client = c || Aws::ElasticBeanstalk::Client.new
  end

  def app
    return Rebi::Application.get_or_create_application(config.app_name)
  end

  def config
    yield Rebi::Config.instance if block_given?
    return Rebi::Config.instance
  end

  def reload!
    config.reload!
  end

  def log mes, prefix=nil
    puts "#{prefix ? "#{colorize_prefix(prefix)}: " : ""}#{mes}"
  end

  COLORS = [:red, :green, :yellow, :blue, :magenta, :cyan, :white]
  def colorize_prefix(prefix)
    h = prefix.chars.inject(0) do |m, c|
      m + c.ord
    end
    return ColorizedString[prefix].colorize(COLORS[h % COLORS.count])
  end

end
