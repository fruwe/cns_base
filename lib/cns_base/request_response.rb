module CnsBase
  # This pattern forces responses to requests.
  # Responses can be delayed, if requests need to wait for other responses of signals.
  # Usage: (ARequestSignal < RequestSignal, BRequestSignal < RequestSignal)
  # publisher.publish ARequestSignal.new
  # in dispatch
  #   if signal.is_a?(ARequestSignal)
  #     if request.deferrers.empty?
  #       request.defer(BRequestSignal.new())
  #     else
  #       request.response = AResponseSignal.new(signal.deferrers.first.b_data)
  #     end
  #   elsif signal.is_a?(BRequestSignal)
  #     publisher.publish BResponseSignal.new(signal)
  #   end
  module RequestResponse
    class RequestResponseListener < Listener
      include CnsBase::Settable
      include CnsBase::Timer

      attr_accessor :listener
      attr_accessor :requests

      attr_accessor :priority_thread
      attr_accessor :priority_deferred_signals

      def initialize publisher
        super publisher

        @listener = SettableSupportListener.new publisher
        @requests = {}

        @priority_thread = nil
        @priority_deferred_signals = []
      end

      def dispatch signal
        result = false

        request_of_response = nil

        if signal.is_a?(ResponseSignal)
          request_of_response = @requests[signal.request_id] || @requests.values.find{|req|req.deferrers.find{|hash|hash[:request].uuid == signal.request_id}}
        end

        if @priority_thread
          unless signal.is_a?(TimeoutSignal) || 
              (signal.is_a?(RequestSignal) && signal.thread_uuid == @priority_thread) ||
              (request_of_response && request_of_response.thread_uuid == @priority_thread)

            @priority_deferred_signals << signal

            CnsBase.logger.debug("defer <#{signal.class}> signal; priority thread #{@priority_thread} (size: #{@priority_deferred_signals.size})") if CnsBase.logger.debug?

            return true
          end
        end

        if signal.is_a?(RequestSignal)
          CnsBase.logger.debug("process request #{signal.uuid}(#{signal.class.name}) thread #{signal.thread_uuid} from #{signal.publisher_uuid} at #{publisher.uuid}") if CnsBase.logger.debug?

          deferred_exception = nil

          # TODO: ExceptionSignal should be processed as well...
          # otherwise, the error behaviour will differ between non request and request
          begin
            result = true if @listener.dispatch signal # the request needs to be deferred or responded to

            if signal.priority?
              signal.reset_priority

              raise "already set to priority mode" if @priority_thread && @priority_thread != signal.thread_uuid

              @priority_thread = signal.thread_uuid
            end

            signal.response = ResponseSignal.new if signal.is_a?(DelaySignal) && !(signal.responded? || signal.deferred?)

            # Exceptions need to be handled or will be raised
            deferred_exception = signal.deferrers.find{|hash|hash[:response].is_a?(ExceptionResponseSignal) && !hash[:response].handled?}
          rescue(Exception) => exception
            deferred_exception = signal.deferrers.find{|hash|hash[:response].is_a?(ExceptionResponseSignal) && !hash[:response].handled?}

            unless deferred_exception
              # error might be caused through an deferred error, thus treat the deferred error with higher priority
              CnsBase::ExceptionSignal.log exception, publisher, signal
              signal.response = ExceptionResponseSignal.new(exception)
            end
          end

          if deferred_exception || !(signal.responded? || signal.deferred?)
            CnsBase.logger.debug("process request #{signal.uuid} was not processed #{signal.pretty_inspect}") if CnsBase.logger.debug?

            exception = deferred_exception ? deferred_exception[:response].exception : RuntimeError.new("RequestResponseListener: RequestSignal did not get an response.\n#{signal.inspect}")

            CnsBase::ExceptionSignal.log(exception, publisher, signal) unless deferred_exception

            signal.response = ExceptionResponseSignal.new(exception)
          end

          if signal.responded?
            @priority_thread = nil if signal.thread_uuid == @priority_thread

            CnsBase.logger.debug("process request #{signal.uuid}(#{signal.class.name}) from ##{signal.publisher_uuid} was responded with #{signal.response.class.name} at ##{publisher.uuid}") if CnsBase.logger.debug?
            if publisher.uuid == signal.publisher_uuid
              publisher.publish signal.response
            else
              publisher.publish(
                CnsBase::Address::AddressRouterSignal.new(
                  signal.response, 
                  CnsBase::Address::PublisherSignalAddress.new(publisher), 
                  CnsBase::Address::PublisherSignalAddress.new(signal.publisher_uuid)
                )
              )
            end

            @requests.delete signal.uuid # delete from queue after completion (only in queue if deferred before)

            # process signals in priority deferred queue
            while not @priority_deferred_signals.empty? && @priority_thread.blank?
              deferred = @priority_deferred_signals.shift

              CnsBase.logger.debug("dispatch deferred <#{deferred.class}> signal; (size: #{@priority_deferred_signals.size})") if CnsBase.logger.debug?

              self.dispatch(deferred)
            end
          elsif signal.deferred?
            CnsBase.logger.debug("process request #{signal.uuid} was deferred") if CnsBase.logger.debug?
            publisher.publish(TimerSignal.new(60, TimeoutSignal.new(signal.uuid))) unless @requests.include? signal.uuid

            @requests[signal.uuid] = signal

            return result
          else
            CnsBase.logger.error("process request #{signal.uuid} was nothing") if CnsBase.logger.error?

            raise
          end
        elsif signal.is_a?(TimeoutSignal)
          CnsBase.logger.debug("timeout signal #{signal.request_id} #{@requests[signal.request_id].blank? ? "CLEARED" : "ERROR"}") if CnsBase.logger.debug?

          request = @requests[signal.request_id]

          # if still in queue, set deferrers's response to exception
          if request
            # set the response off all deferrers, waiting for an response to an exception signal.
            request.deferrers.each do |hash|
              unless hash[:response]
                exception = RuntimeError.new("Request Timed Out")

                CnsBase::ExceptionSignal.log exception, publisher, signal

                exception_signal = ExceptionResponseSignal.new(exception)
                exception_signal.request_id = hash[:request].uuid
                self.dispatch(exception_signal)
              end
            end

            CnsBase.logger.warn("request #{signal.request_id} still deferred after Time Out") if CnsBase.logger.warn? && (request.deferred? || @requests[signal.request_id])

            result = true
          end
        elsif signal.is_a?(ResponseSignal)
          CnsBase.logger.debug("got response #{signal.request_id}") if CnsBase.logger.debug?

          request = request_of_response

          if request
            CnsBase.logger.debug(" => response to deferred request") if CnsBase.logger.debug?

            request.response = signal # adds the response to the queue

#              result = true if @listener.dispatch signal  # ResponseSignal might be processed, but not sure, whether this is good or not

            # dispatch request again, if all deferred signals were responded to.
            CnsBase.logger.debug(" => request still deferred") if CnsBase.logger.debug? && request.deferred?

            unless request.deferred?
              CnsBase.logger.debug(" => process request again") if CnsBase.logger.debug?

              result = true if self.dispatch request # request needs to be dispatched, in order to finish the request
            end
          else
            CnsBase.logger.debug(" => normal response") if CnsBase.logger.debug?

            result = true if @listener.dispatch signal

            # Exceptions need to be handled or will be raised
            raise signal.exception if signal.is_a?(ExceptionResponseSignal) && !signal.handled?
          end
        else
          result = true if @listener.dispatch signal
        end

        return result
      end
    end

#      $REQUESTS = 0
#      $DEFERS = 0

    class RequestSignal < CnsBase::Signal
      attr_accessor :uuid
      attr_accessor :response
      attr_accessor :deferrers
      attr_accessor :publisher_uuid
      attr_accessor :thread_uuid

      def initialize publisher_or_uuid, name=nil, params=nil
        super(name, params)

        raise if publisher_or_uuid.blank?

#          $REQUESTS += 1
#          CnsBase.logger.debug($REQUESTS.to_s + " " + self.class.name) if CnsBase.logger.debug?

        @thread_uuid = nil
        @uuid = CnsBase.uuid
        @response = nil
        @deferrers = []
        @publisher_uuid = publisher_or_uuid.is_a?(CnsBase::Publisher) ? publisher_or_uuid.uuid : publisher_or_uuid
        @pri = nil
      end

      # priority events will defer all other requests, which are not coming from the same thread
      def priority!
        raise "priority mode must be set before deferring or responding" unless @response.blank? && deferrers.empty?

        @thread_uuid = @uuid

        @pri = true
      end

      # returns and resets priority
      def priority?
        @pri
      end

      def reset_priority
        tmp = @pri
        @pri = nil
        tmp
      end

      # defers a response with another RequestSignal
      def defer! publisher, signal
        request = signal

        if !signal.is_a?(RequestSignal) && signal.respond_to?(:signal) && signal.signal.is_a?(RequestSignal)
          request = signal.signal
        end

        raise "signal is not a request signal" unless request.is_a?(RequestSignal)
        raise "request already responded" if responded?

#          $DEFERS += 1
#          CnsBase.logger.debug($DEFERS.to_s + " defers; request #{self.uuid}") if CnsBase.logger.debug?

        if @thread_uuid
          request.thread_uuid = @thread_uuid

          if !signal.is_a?(RequestSignal) && signal.respond_to?(:signal) && signal.signal.is_a?(RequestSignal)
            signal.signal = request
          end
        end

        @deferrers << {:request => request}

        publisher.publish signal

        signal
      end

      def delay! publisher, delay
        defer!(publisher, CnsBase::Timer::TimerSignal.new(delay, DelaySignal.new(publisher)))
      end

      def response= signal
        CnsBase.logger.debug("response equal; request #{self.uuid}") if CnsBase.logger.debug?

        return if @response.is_a?(ExceptionResponseSignal)

        @response = nil if signal.is_a?(ExceptionResponseSignal) # response can be overwritten by exception signals

        raise "signal is blank" if signal.blank?

        unless @response.blank?
          msg = []
          msg << "response is already set" 
          msg << "now: #{@response.class.name} deferred:#{deferred?} responded:#{responded?} deferred_response:#{deferred_response?}"
          msg << "sig: #{signal.class.name}"
          raise msg.join("\n")
        end

        raise "signal is not a response signal" unless signal.is_a?(ResponseSignal)

        if signal.request_id.blank? || signal.request_id == @uuid
          raise "request's response can not be written while deferred" if deferred? && !signal.is_a?(ExceptionResponseSignal)

          signal.request_id = @uuid
          @response = signal
          @tmp = nil
        else
          deferrer = @deferrers.find{|hash|hash[:request].uuid == signal.request_id}

          raise "response for unknown deferred request" unless deferrer

          if deferrer[:response]
            msg = []
            msg << "response for deferred request is already set"
            msg << "now: #{deferrer.pretty_inspect}"
            msg << "sig: #{signal.pretty_inspect}"
            raise msg.join("\n")
          end

#            $DEFERS -= 1
#            CnsBase.logger.debug($DEFERS.to_s + " defers; request #{self.uuid}") if CnsBase.logger.debug?

          deferrer[:response] = signal
        end

        signal
      end

      def tmp
        raise "tmp can not be used if responded" if responded?
        @tmp ||= nil
      end

      def tmp= val
        raise "tmp can not be used if responded" if responded?
        @tmp = val
      end

      def deferred?
        !!@deferrers.find{|deferrer|not deferrer.include?(:response)}
      end

      def responded?
        !!@response
      end

      def deferred_response?
        !(@response || @deferrers.empty? || deferred?)
      end

      def raise_on_deferred_error!
        exc = @deferrers.find{|deferrer|deferrer[:response].is_a?(ExceptionResponseSignal)}
        raise exc[:response].exception if exc
        true
      end
    end

    class ResponseSignal < CnsBase::Signal
      attr_accessor :request_id
      attr_accessor :uid

      def initialize name=nil, params=nil
        super(name, params)

#          $REQUESTS -= 1
#          CnsBase.logger.debug($REQUESTS.to_s + " " + self.class.name) if CnsBase.logger.debug?

        @request_id = nil
        @uid = CnsBase.uuid
      end
    end

    class ExceptionResponseSignal < ResponseSignal
      attr_accessor :exception
      attr_accessor :handled

      def initialize exception, name=nil, params=nil
        super(name, params)

        @exception = exception
        @handled = false
      end

      def handled!
        @handled = true
      end

      def handled?
        @handled
      end
    end

    class TimeoutSignal < CnsBase::Signal
      attr_accessor :request_id

      def initialize request_id, name=nil, params=nil
        super(name, params)

        @request_id = request_id
      end
    end

    class DelaySignal < RequestSignal
      def initialize publisher_or_uuid, name=nil, params=nil
        super
      end
    end
  end
end
