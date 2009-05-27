require File.dirname(__FILE__) + '/test_helper.rb'

$A = 0

class TestCnsBase < Test::Unit::TestCase

  def setup
    CnsBase::Cas::CasControlHelper.shutdown
  end

  def test_init
    puts "This test should show four lines with <TestCreationCore> inside."
    
    CnsBase::Cas::CasControlHelper.init INIT_HASH
    CnsBase::Cas::CasControlHelper.confirm_start
    CnsBase::Cas::CasControlHelper.shutdown

    puts
    puts
    puts
    puts
    puts

    CnsBase::Cas::CasControlHelper.init INIT_HASH
    CnsBase::Cas::CasControlHelper.confirm_start
    
    ao = TestAccess.new
    puts "should be 2.5"
    puts(ao.divide(5.0,2.0))
    puts "should be exception"
    puts "try http to google.com"
    puts(ao.http("http://www.google.co.jp").pretty_inspect)
    puts(ao.http("http://www.google.co.jp").pretty_inspect)
    puts "try http to not_existing.com"
    begin
      CnsBase.logger.level = Logger::FATAL
      ao.http("http://www.not_existing.com")
    rescue => exception
      puts exception.class.name
      puts exception.message
    end
    CnsBase.logger.level = Logger::INFO

    begin
      CnsBase.logger.level = Logger::FATAL
      pust(ao.divide(5,0))
    rescue => exception
      puts exception.class.name
      puts exception.message
    end
    CnsBase.logger.level = Logger::INFO
    
    CnsBase::Cas::CasControlHelper.shutdown

    puts
    puts
    puts
    puts
    puts
  end

  def test_request_response
    publisher = TestPublisher.new
    listener = TestListener.new( publisher )
    
    rr = CnsBase::RequestResponse::RequestResponseListener.new publisher
    
    rr.dispatch( CnsBase::Settable::SetListenerTypeSignal.new( listener ) )
    
    assert publisher.queue.size == 0
    assert listener.queue.size == 0
    
    # test normal non request signal
    puts "-" * 100
    rr.dispatch(CnsBase::Signal.new(:test))

    assert publisher.queue.size == 0
    assert listener.queue.size == 1
    assert listener.queue[0].name == :test
    
    publisher.queue.clear
    listener.queue.clear
    
    # test only response
    puts "-" * 100
    rr.dispatch(CnsBase::RequestResponse::ResponseSignal.new(:test2))

    assert publisher.queue.size == 0
    assert listener.queue.size == 1
    assert listener.queue[0].name == :test2

    publisher.queue.clear
    listener.queue.clear

    # test unhandled exception response
    puts "-" * 100
    
    begin
      rr.dispatch(CnsBase::RequestResponse::ExceptionResponseSignal.new(RuntimeError.new("exception")))
      assert false
    rescue => exception
      puts exception.message
      assert exception.message == "exception"
    end

    assert publisher.queue.size == 0
    assert listener.queue.size == 1
    assert listener.queue[0].is_a?(CnsBase::RequestResponse::ExceptionResponseSignal)

    publisher.queue.clear
    listener.queue.clear

    # test handled exception response
    puts "-" * 100
    
    rr.dispatch(CnsBase::RequestResponse::ExceptionResponseSignal.new(RuntimeError.new("handled exception")))

    assert publisher.queue.size == 0
    assert listener.queue.size == 1
    assert listener.queue[0].is_a?(CnsBase::RequestResponse::ExceptionResponseSignal)

    publisher.queue.clear
    listener.queue.clear
    
    # test request without response
    puts "-" * 100
    rr.dispatch(CnsBase::RequestResponse::RequestSignal.new(publisher, :test3))

    assert publisher.queue.size == 1
    assert listener.queue.size == 1
    assert publisher.queue[0].is_a?(CnsBase::RequestResponse::ExceptionResponseSignal)
    assert publisher.queue[0].exception.message.starts_with?("RequestResponseListener: RequestSignal did not get an response.")
    assert listener.queue[0].name == :test3

    publisher.queue.clear
    listener.queue.clear

    # test request with wrong class response
    puts "-" * 100
    rr.dispatch(CnsBase::RequestResponse::RequestSignal.new(publisher, :test_wrong_class_response))

    assert publisher.queue.size == 1
    assert listener.queue.size == 1
    assert publisher.queue[0].is_a?(CnsBase::RequestResponse::ExceptionResponseSignal)
    puts publisher.queue[0].exception
    assert publisher.queue[0].exception.message.starts_with?("signal is not a response signal")
    assert listener.queue[0].name == :test_wrong_class_response

    publisher.queue.clear
    listener.queue.clear

    # test request with nil response
    puts "-" * 100
    rr.dispatch(CnsBase::RequestResponse::RequestSignal.new(publisher, :test_nil_response))

    assert publisher.queue.size == 1
    assert listener.queue.size == 1
    assert publisher.queue[0].is_a?(CnsBase::RequestResponse::ExceptionResponseSignal)
    puts publisher.queue[0].exception
    assert publisher.queue[0].exception.message.starts_with?("signal is blank")
    assert listener.queue[0].name == :test_nil_response

    publisher.queue.clear
    listener.queue.clear
    
    # test request with double response
    puts "-" * 100
    rr.dispatch(CnsBase::RequestResponse::RequestSignal.new(publisher, :test_double_response))

    assert publisher.queue.size == 1
    assert listener.queue.size == 1
    assert publisher.queue[0].is_a?(CnsBase::RequestResponse::ExceptionResponseSignal)
    puts publisher.queue[0].exception
    assert publisher.queue[0].exception.message.starts_with?("response is already set")
    assert listener.queue[0].name == :test_double_response

    publisher.queue.clear
    listener.queue.clear

    # test_non_set_published_response
    puts "-" * 100
    rr.dispatch(CnsBase::RequestResponse::RequestSignal.new(publisher, :test_non_set_published_response))

    assert publisher.queue.size == 2
    assert listener.queue.size == 1
    assert publisher.queue[0].is_a?(CnsBase::RequestResponse::ResponseSignal)
    assert publisher.queue[0].name == :wrong_response
    assert publisher.queue[1].is_a?(CnsBase::RequestResponse::ExceptionResponseSignal)
    puts publisher.queue[1].exception
    assert publisher.queue[1].exception.message.starts_with?("RequestResponseListener: RequestSignal did not get an response.")
    assert listener.queue[0].name == :test_non_set_published_response

    publisher.queue.clear
    listener.queue.clear

    # test_set_and_published_response
    puts "-" * 100
    rr.dispatch(CnsBase::RequestResponse::RequestSignal.new(publisher, :test_set_and_published_response))

    assert publisher.queue.size == 2
    assert listener.queue.size == 1
    assert publisher.queue[0].is_a?(CnsBase::RequestResponse::ResponseSignal)
    assert publisher.queue[0].name == :wrong_response
    assert publisher.queue[1].is_a?(CnsBase::RequestResponse::ResponseSignal)
    assert publisher.queue[1].name == :wrong_response
    assert listener.queue[0].name == :test_set_and_published_response
    
    rr.dispatch(publisher.queue[0])

    assert publisher.queue.size == 2
    assert listener.queue.size == 2
    
    rr.dispatch(publisher.queue[1])

    assert publisher.queue.size == 2
    assert listener.queue.size == 3

    publisher.queue.clear
    listener.queue.clear

    # test_deferred_request
    puts "-" * 100
    rr.dispatch(CnsBase::RequestResponse::RequestSignal.new(publisher, :test_deferred_request))

    assert publisher.queue.size == 2
    assert listener.queue.size == 1
    
    assert publisher.queue[0].is_a?(CnsBase::RequestResponse::RequestSignal)
    assert publisher.queue[0].name == :deferred_request
    assert publisher.queue[1].is_a?(CnsBase::Timer::TimerSignal)
    assert listener.queue[0].name == :test_deferred_request

    rr.dispatch(publisher.queue[1].signal) # try timer sig (will be deferred with another timer signal, as the event itself is deferred)

    pp publisher.queue

    assert publisher.queue.size == 3
    assert listener.queue.size == 2
    assert publisher.queue[0].is_a?(CnsBase::RequestResponse::RequestSignal)
    assert publisher.queue[0].name == :deferred_request
    assert publisher.queue[1].is_a?(CnsBase::Timer::TimerSignal)
    assert publisher.queue[2].is_a?(CnsBase::RequestResponse::ExceptionResponseSignal)
    puts publisher.queue[2].exception
    assert publisher.queue[2].exception.message.starts_with?("Request Timed Out")
    assert listener.queue[0].name == :test_deferred_request
    assert listener.queue[1].name == :test_deferred_request

    publisher.queue.clear
    listener.queue.clear

    # test_deferred_request_with_response
    puts "-" * 100
    rr.dispatch(CnsBase::RequestResponse::RequestSignal.new(publisher, :test_deferred_request_with_response))

    assert publisher.queue.size == 2
    assert listener.queue.size == 1
    assert publisher.queue[0].is_a?(CnsBase::RequestResponse::RequestSignal)
    assert publisher.queue[0].name == :deferred_request
    assert publisher.queue[1].is_a?(CnsBase::Timer::TimerSignal)
    assert listener.queue[0].name == :test_deferred_request_with_response

    rr.dispatch(publisher.queue[0])

    assert publisher.queue.size == 3
    assert listener.queue.size == 2
    assert publisher.queue[0].is_a?(CnsBase::RequestResponse::RequestSignal)
    assert publisher.queue[0].name == :deferred_request
    assert publisher.queue[1].is_a?(CnsBase::Timer::TimerSignal)
    assert publisher.queue[2].is_a?(CnsBase::RequestResponse::ResponseSignal)
    assert publisher.queue[2].name == :response_from_deferred_object
    assert listener.queue[0].name == :test_deferred_request_with_response
    assert listener.queue[1].name == :deferred_request

    rr.dispatch(publisher.queue[2])
    
    pp listener.queue

    assert publisher.queue.size == 4
    assert listener.queue.size == 3
    assert publisher.queue[0].is_a?(CnsBase::RequestResponse::RequestSignal)
    assert publisher.queue[0].name == :deferred_request
    assert publisher.queue[1].is_a?(CnsBase::Timer::TimerSignal)
    assert publisher.queue[2].is_a?(CnsBase::RequestResponse::ResponseSignal)
    assert publisher.queue[2].name == :response_from_deferred_object
    assert publisher.queue[3].is_a?(CnsBase::RequestResponse::ResponseSignal)
    assert publisher.queue[3].name == :response_from_deferred_object_inner
    assert listener.queue[0].name == :test_deferred_request_with_response
    assert listener.queue[1].name == :deferred_request
    assert listener.queue[2].name == :test_deferred_request_with_response

    publisher.queue.clear
    listener.queue.clear
  end
  
  def test_speed
    CnsBase::Cas::CasControlHelper.init INIT_HASH
    CnsBase::Cas::CasControlHelper.confirm_start
    
    ao = TestAccess.new

    CnsBase.logger.level = Logger::WARN

    start = Time.now
    duration = 15
    end_time = start + duration
    size = 0
    
    while Time.now < end_time
      res = ao.http("http://www.google.co.jp")
      size += res[:content].size
      puts "DONE REQUEST, STILL #{(end_time.to_i - Time.now.to_i)} secs"
    end
    
    puts "size: #{size} speed: #{(size / (Time.now.to_f - start.to_f))/1024} KB/SEC"
    
    puts "START TEST 2"

    start = Time.now
    end_time = start + duration
    size = 0
    
    while Time.now < end_time
      res = ao.http_multiple("http://www.google.co.jp")
      size += res[:content].size
      puts "DONE REQUEST, STILL #{(end_time.to_i - Time.now.to_i)} secs"
    end
    
    puts "size: #{size} speed: #{(size / (Time.now.to_f - start.to_f))/1024} KB/SEC"
    
    CnsBase::Cas::CasControlHelper.shutdown

    puts
    puts
    puts
    puts
    puts
  end
end
