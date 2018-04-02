class Rebi::EB

  attr_reader :client
  def initialize client=Aws::ElasticBeanstalk::Client.new
    @client = client
  end

  def applications
    client.describe_applications.applications.map(&:application_name)
  end

  def solution_stacks
    @solution_stacks = client.list_available_solution_stacks.solution_stacks.map do |s|
      stacks_from_string s
    end
  end

  def platforms
    @platforms ||= solution_stacks.map do |st|
      st["platform"]
    end.uniq
  end

  def versions_by_platform platform
    raise "Invalid platform" unless platforms.include?(platform)

    solution_stacks.select do |st|
      st["platform"] == platform
    end.map do |st|
      st["version"]
    end.uniq
  end

  def get_solution_stack platform, version
    solution_stacks.find do |st|
      st["platform"] == platform && st["version"] == version
    end["solution_stack"]
  end

  def method_missing(m, *args, &block)
    client.send(m, *args, &block)
  end

  private

  def stacks_from_string s
    res = {}.with_indifferent_access
    res[:platform] = s.match('.+running\s([^0-9]+).*')&.captures&.first.try(:strip)
    res[:version] = s.match('.+running\s(.*)')&.captures&.first.try(:strip)
    res[:server] = s.match('(.*)\srunning\s.*')&.captures&.first.try(:strip)
    res[:stack_version] = s.match('.+v([0-9.]+)\srunning\s.*')&.captures&.first.try(:strip)
    res[:solution_stack] = s
    res
  end
end
