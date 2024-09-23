require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'

  gem "excon"

  gem "activesupport"
  gem "nokogiri"

  gem "robotstxt"
end

require "active_support"

#TODO: Add optsparse

class RobotsDeniedError < StandardError

end

class ProductionCheck

  attr_reader :protocol, :host, :useragent

  attr_reader :obey_robots
  attr_reader :robots

  def initialize options: Hash.new
    @protocol = "https"
    @host = options[:host]

    @sitemaps = Hash.new

    @obey_robots = true

    @locations = Set["/"]

    @problem_status = Array.new
    @missing_description = Array.new
    @missing_keywords = Array.new

    # Safari 18; Mac OS X 15 Sequioa
    # @useragent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    @useragent = "ProductionCheck/1 (https://github.com/phil/production-check)"
  end

  def start
    puts "Starting ..."
    load_robots
    check_locations

    puts "==========="
    puts "Problem status codes"
    @problem_status.each do |path|
      puts path
    end

    puts "==========="
    puts "Missing Description"
    @missing_description.each do |path|
      puts path
    end
    puts "==========="
    puts "Missing Keywords"
    @missing_keywords.each do |path|
      puts path
    end
  end

  def load_robots
    puts "loading robots.txt"

    @robots = Robotstxt::Parser.new(useragent)
    robots.get(build_url(path: "robots.txt"))
  end

  def check_locations
    while ( path = next_location ) do
      check_location path
    end
  end

  def check_location path
    response = get path: path

    @problem_status << "#{response.status} #{path}" if response.status != 200

    case response.headers["Content-Type"]
    when /text\/html/
      # Load file into nokogiri
      document = Nokogiri.HTML(response.body)
      @missing_description << path if (document.at("head > meta[name=description]")["value"].blank? rescue true)
      @missing_keywords << path if (document.at("head > meta[name=keywords]")["value"].blank? rescue true)

      document.search("a[href]").map { |a| a["href"] }.each do |href|
        add_location href
      end
    end

  rescue RobotsDeniedError => e
    puts "Skipping path: #{e.message}"
  end

  def get path: ""
    raise RobotsDeniedError.new unless robots.allowed?(path)

    Excon.get(build_url(path: path))
  end

  def build_url path: nil
    File.join("#{protocol}://#{host}", path)
  end

  def add_location location
    return if location == "#"
    uri = URI.parse(location)
    return if uri.host && uri.host != host
    @locations << uri.path
  end

  def next_location
    @location_index ||= -1
    @location_index += 1
    @locations.to_a[@location_index]
  end

end

ProductionCheck.new(options: {host: "maniacalrobot.co.uk"}).start
