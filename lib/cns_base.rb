require 'rubygems'
require 'monitor'
require 'extensions/all'
require 'uuidtools'
require 'fastthread'
require 'yaml'
require 'httpclient'
require 'rufus/scheduler'
require 'uri'
require 'logger'
require 'zlib'
require 'stringio'
require 'ezcrypto'
#require 'ruby-debug'

class Object
  def blank?
    if respond_to?(:empty?) && respond_to?(:strip)
      empty? or strip.empty?
    elsif respond_to?(:empty?)
      empty?
    else
      !self
    end
  end
end

module CnsBase
  VERSION = '0.0.5'

  def self.logger
    @LOGGER ||= nil

    unless @LOGGER
      @LOGGER = Logger.new(STDOUT)
#    @LOGGER ||= Logger.new("log/application.log")
      @LOGGER.level = Logger::INFO
    end

    @LOGGER
  end
  
#  $UUID = 0
#  $UUID_MUTEX = Mutex.new
  def self.uuid
#    $UUID_MUTEX.synchronize do
#      $UUID += 1
#    end
    UUID.timestamp_create.hexdigest.to_sym
  end
end

YAML.add_domain_type("ruby/class,2007", "") do |type, val|
  klass = type.split(':').last.constantize
  YAML.object_maker(klass, val)
end

class String
  def gzip
    ostream = StringIO.new

    gz = Zlib::GzipWriter.new(ostream)
    begin 
      gz.write(self)
    ensure
      gz.close
    end

    ostream.string
  end

  def gunzip
    result = nil

    ostream = StringIO.new self

    gz = Zlib::GzipReader.new(ostream)
    begin 
      result = gz.read
    ensure
      gz.close
    end

    result
  end

  def trim
    self.split.join
  end

  def encode
    return CGI.escape(Base64.encode64(self))
  end

  def decode
    return Base64.decode64(CGI.unescape(self))
  end
  
  $COMMON_PASSWORD = "hdashf38hehyv332casdn3l"
  $COMMON_SALT = "747hevjo348hcoeh3"
  
  def encrypt pepper = ""
    EzCrypto::Key.encrypt_with_password($COMMON_PASSWORD, $COMMON_SALT + pepper.to_s, self) || ""
  end

  def decrypt pepper = ""
    EzCrypto::Key.decrypt_with_password($COMMON_PASSWORD, $COMMON_SALT + pepper.to_s, self) || ""
  end
end

class Class
  def self.yaml_new( klass, tag, val )
    clazz = Object
    
    val.split("::").each do |name|
      clazz = clazz.const_get(name)
    end
    
    clazz
  end
  
  yaml_as "tag:fruwe.com,2009:class"
  
	def to_yaml( opts = {} )
		YAML::quick_emit( nil, opts ) do |out|
      out.scalar( taguri, self.name, :plain )
    end
	end
end

class Exception
  yaml_as "tag:ruby.yaml.org,2002:exception"
  def Exception.yaml_new( klass, tag, val )
    o = klass.new val.delete( 'message' )
    o.set_backtrace(val.delete('backtrace'))
    
    val.each_pair do |k,v|
        o.instance_variable_set("@#{k}", v)
    end
    
    o
  end
	def to_yaml( opts = {} )
		YAML::quick_emit( object_id, opts ) do |out|
      out.map( taguri, to_yaml_style ) do |map|
        map.add( 'message', message )
        map.add( 'backtrace', backtrace )
				to_yaml_properties.each do |m|
          map.add( m[1..-1], instance_variable_get( m ) )
        end 
      end
    end
	end
end

$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'cns_base/signal'
require 'cns_base/signals'
require 'cns_base/listener'
require 'cns_base/publisher'

require 'cns_base/provider'
require 'cns_base/settable'
require 'cns_base/filter'
require 'cns_base/timer'
require 'cns_base/request_response'
require 'cns_base/queue'
require 'cns_base/publisher_connection'
require 'cns_base/routing'
require 'cns_base/address'
require 'cns_base/http_client'

require 'cns_base/cluster'

require 'cns_base/cas'
require 'cns_base/stub'

# Poor Man's Fiber (API compatible Thread based Fiber implementation for Ruby 1.8)
# (c) 2008 Aman Gupta (tmm1)

unless defined? Fiber
  require 'thread'

  class FiberError < StandardError; end

  class Fiber
    def initialize
      raise ArgumentError, 'new Fiber requires a block' unless block_given?

      @yield = Queue.new
      @resume = Queue.new

      @thread = Thread.new{ @yield.push [ *yield(*@resume.pop) ] }
      @thread.abort_on_exception = true
      @thread[:fiber] = self
    end
    
    attr_reader :thread

    def resume *args
      raise FiberError, 'dead fiber called' unless @thread.alive?
      @resume.push(args)
      result = @yield.pop
      result.size > 1 ? result : result.first
    end
    
    def yield *args
      @yield.push(args)
      result = @resume.pop
      result.size > 1 ? result : result.first
    end
    
    def self.yield *args
      raise FiberError, "can't yield from root fiber" unless fiber = Thread.current[:fiber]
      fiber.yield(*args)
    end

    def self.current
      Thread.current[:fiber] or raise FiberError, 'not inside a fiber'
    end

    def inspect
      "#<#{self.class}:0x#{self.object_id.to_s(16)}>"
    end
  end
end
