require 'stringio'
require 'test/unit'
require File.dirname(__FILE__) + '/../lib/cns_base'

class TestCreationCore < CnsBase::Cluster::ClusterCore
  def initialize publisher
    super publisher
  end
  
  def dispatch signal
    if signal.is_a?(CnsBase::Cluster::ClusterCreationSignal)
      CnsBase.logger.fatal(("TestCreationCore: " + ("*" * 10) + signal.class.name)) if CnsBase.logger.fatal?
      CnsBase.logger.fatal(("TestCreationCore: " + ("*" * 10) + signal.params.inspect)) if CnsBase.logger.fatal?
    end
  end
end

class TestDivisionCore < CnsBase::Cluster::ClusterCore
  def initialize publisher
    super publisher
  end
  
  def dispatch signal
    if signal.is_a?(CnsBase::RequestResponse::RequestSignal) && signal.name == :divide
      CnsBase.logger.fatal("Divide:#{signal[:a]} / #{signal[:b]}") if CnsBase.logger.fatal?
      result = signal[:a] / signal[:b]
      signal.response = CnsBase::RequestResponse::ResponseSignal.new(:division_result, {:result => result})
    end

    if signal.is_a?(CnsBase::RequestResponse::RequestSignal) && signal.name == :http
      if signal.deferred_response? && signal.raise_on_deferred_error!
        CnsBase.logger.fatal("Http Access to :#{signal[:url]}") if CnsBase.logger.fatal?

        res = signal.deferrers.first[:response]
        
        signal.response = CnsBase::RequestResponse::ResponseSignal.new(:http_result, {:content => res.content, :status => res.status})
      else
        event = CnsBase::HttpClient::HttpRequestSignal.new(publisher, :get, signal[:url])
        
        signal.defer! publisher, event
      end
    end

    if signal.is_a?(CnsBase::RequestResponse::RequestSignal) && signal.name == :http_multiple
      if signal.deferred_response? && signal.raise_on_deferred_error!
        CnsBase.logger.fatal("Http Access to :#{signal[:url]}") if CnsBase.logger.fatal?

        res = signal.deferrers.first[:response]
        contents = signal.deferrers.collect{|hash|hash[:response].content}.join
        
        signal.response = CnsBase::RequestResponse::ResponseSignal.new(:http_result, {:content => contents, :status => res.status})
      else
        event = CnsBase::HttpClient::HttpRequestSignal.new(publisher, :get, "http://www.yahoo.com")
        signal.defer! publisher, event

        event = CnsBase::HttpClient::HttpRequestSignal.new(publisher, :get, "http://www.google.com")
        signal.defer! publisher, event

        event = CnsBase::HttpClient::HttpRequestSignal.new(publisher, :get, "http://www.yahoo.de")
        signal.defer! publisher, event

        event = CnsBase::HttpClient::HttpRequestSignal.new(publisher, :get, "http://www.google.co.jp")
        signal.defer! publisher, event

        event = CnsBase::HttpClient::HttpRequestSignal.new(publisher, :get, "http://www.yahoo.com")
        signal.defer! publisher, event

        event = CnsBase::HttpClient::HttpRequestSignal.new(publisher, :get, "http://www.google.com")
        signal.defer! publisher, event

        event = CnsBase::HttpClient::HttpRequestSignal.new(publisher, :get, "http://www.yahoo.de")
        signal.defer! publisher, event

        event = CnsBase::HttpClient::HttpRequestSignal.new(publisher, :get, "http://www.google.co.jp")
        signal.defer! publisher, event
      end
    end
  end
end

class TestAccess < CnsBase::Stub::StubAccessSupport
  cns_method :divide, [:a, :b] do |name, params|
    params[:result]
  end

  cns_method :http, [:url] do |name, params|
    params
  end

  cns_method :http_multiple, [:url] do |name, params|
    params
  end
  
  def initialize
    super "/divide"
  end
end

class TestPublisher < CnsBase::Publisher
  attr_accessor :queue
  
  def initialize
    super
    @queue = []
  end
  
  def publish signal
    queue << signal
  end
end

class TestListener < CnsBase::Listener
  attr_accessor :queue
  
  def initialize publisher
    super
    @queue = []
  end
  
  def dispatch signal
    queue << signal
    
    if signal.name == :test_wrong_class_response
      signal.response = CnsBase::Signal.new(:response)
    elsif signal.is_a?(CnsBase::RequestResponse::ExceptionResponseSignal) && signal.exception.message == "handled exception"
      signal.handled!
    elsif signal.name == :test_nil_response
      signal.response = nil
    elsif signal.name == :test_double_response
      signal.response = CnsBase::RequestResponse::ResponseSignal.new(:response)
      signal.response = CnsBase::RequestResponse::ResponseSignal.new(:response)
    elsif signal.name == :test_non_set_published_response
      publisher.publish(CnsBase::RequestResponse::ResponseSignal.new(:wrong_response))
    elsif signal.name == :test_set_and_published_response
      r = CnsBase::RequestResponse::ResponseSignal.new(:wrong_response)
      signal.response = r
      publisher.publish r
    elsif signal.name == :test_deferred_request && !signal.deferred_response?
      signal.defer! publisher, CnsBase::RequestResponse::RequestSignal.new(publisher, :deferred_request)
    elsif signal.name == :test_deferred_request_with_response && !signal.deferred_response?
      signal.defer! publisher, CnsBase::RequestResponse::RequestSignal.new(publisher, :deferred_request)
    elsif signal.name == :test_deferred_request_with_response && signal.deferred_response?
      signal.response = CnsBase::RequestResponse::ResponseSignal.new(:response_from_deferred_object_inner) # unless signal.deferrers.first[:response].is_a?(CnsBase::RequestResponse::ExceptionResponseSignal)
    elsif signal.name == :deferred_request
      signal.response = CnsBase::RequestResponse::ResponseSignal.new(:response_from_deferred_object)
    elsif signal.name == :test_normal_response
      signal.response = CnsBase::RequestResponse::ResponseSignal.new(:response)
    end
  end
end

INIT_HASH = 
{
  :params => 
  [
    {
      :class => TestCreationCore,
      :params => {},
      :uri => "/test1"
    },
    {
      :class => TestCreationCore,
      :params => {},
      :uri => "/test2"
    },
    {
      :class => TestDivisionCore,
      :params => {},
      :uri => "/divide"
    },
    {
      :class => CnsBase::Stub::StubControlClusterCore, 
      :uri => "/synq_access_0"
    }
  ],
  :class => CnsBase::Cas::ClusterApplicationServer
}
