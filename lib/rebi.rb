require 'active_support/all'
require 'aws-sdk-ec2'
require 'aws-sdk-s3'
require 'aws-sdk-elasticbeanstalk'
require 'aws-sdk-iam'
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
require 'thread'
require 'thwait'
require 'subprocess'
require 'pathspec'

require 'rebi/log'
require 'rebi/erb_helper'
require 'rebi/zip_helper'
require 'rebi/application'
require 'rebi/environment'
require 'rebi/config'
require 'rebi/config_environment'
require 'rebi/error'
require 'rebi/ec2'
require 'rebi/eb'
require 'rebi/init_service'
require 'rebi/version'

# Dotenv.load

module Rebi
  include Rebi::Log

  extend self
  attr_accessor :config_file
  @config_file = "config/rebi.yml"

  def root
    Dir.pwd
  end

  def eb c=nil
    @@eb = Rebi::EB.new
  end

  def ec2
    @@ec2_client = Rebi::EC2.new
  end

  def iam
    @@iam_client = Aws::IAM::Client.new
  end

  def s3
    @@s3_client = Aws::S3::Client.new
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

  def init stage_name, env_name
    init = Rebi::InitService.new(stage_name, env_name)
    init.execute
  end

end
