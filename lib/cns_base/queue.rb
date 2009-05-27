module CnsBase
  # Used for queueing events and thread based event publishing
  # TODO: This creates a thread for each cluster. Instead I should use a round robin with a central queue.
  module Queue
    # Is a listener, which queues signals, until a proceed signal comes
    class QueuableSupportListener < Listener
      include CnsBase::Settable
      
      attr_accessor :listener
      attr_accessor :queue
      attr_accessor :onoff
      
      def initialize publisher
        super publisher
        
        @queue = Object::Queue.new
        @listener = SettableSupportListener.new publisher
        self.onoff = false
      end

      def onoff= value
        @thread ||= nil
        
        @onoff = value
        
        if value == true
          raise if @thread
          
          @thread = Thread.new{run}
        elsif value == false && @thread
          CnsBase.logger.info("GRACEFULLY SHUTDOWN QueuableSupportListener") if CnsBase.logger.info?
          
          @thread = nil
        end
      end
      
      def run
        CnsBase.logger.debug("QueuableSupportListener thread started") if CnsBase.logger.debug?
        
        signal = nil
        
        while self.onoff
          CnsBase::ExceptionSignal.try(publisher, signal) do 
            signal = @queue.pop
            dispatch(ProceedSignal.new(signal))
          end
        end
        
        # flush queue
        # TODO: Queue might not empty even after this...
        CnsBase::ExceptionSignal.try(publisher, signal) do 
          signal = @queue.pop unless @queue.empty?
          dispatch(ProceedSignal.new(signal))
        end
      end
      
      def process next_signal
        result = false 

        next_signal = @queue.empty? ? nil : @queue.pop unless next_signal
        
        while next_signal
          CnsBase.logger.debug("QUEUE: Process #{next_signal.class.name} (left: #{@queue.length})") if CnsBase.logger.debug?

          benchmark
        
          CnsBase::ExceptionSignal.try(publisher, next_signal) do 
            result = true if @listener.dispatch next_signal
          end
          
          next_signal = @queue.empty? ? nil : @queue.pop
        end
        
        return result
      end
      
      def dispatch signal
        if signal.is_a?(ProceedSignal) && self.onoff == true
          return process(signal.signal)
        elsif self.onoff == true
          CnsBase.logger.debug("QUEUE: Put in queue #{signal.class.name} (size: #{queue.size})") if CnsBase.logger.debug?
          
          @queue << signal
          
          return true
        else
          next_signal = nil
          
          if signal.is_a?(ProceedSignal)
            next_signal = signal.signal if signal.signal
          else
            CnsBase.logger.debug("QUEUE: Put in queue #{signal.class.name} (size: #{queue.size})") if CnsBase.logger.debug?
            @queue << signal
          end
          
          return process(next_signal)
        end
      end

      private
      
      $DISPATCH_COUNTER = 0
      $DISPATCH_TIME = Time.now
      $DISPATCH_MUTEX = Mutex.new
      $DISPATCH_START = Time.now
      $DISPATCH_TOTAL = 0
      def benchmark
        $DISPATCH_MUTEX.synchronize do
          $DISPATCH_COUNTER += 1
          $DISPATCH_TOTAL += 1

          time_diff = (Time.now.to_f - $DISPATCH_TIME.to_f)

          if time_diff > 10
            total_diff = (Time.now.to_f - $DISPATCH_START.to_f)

            CnsBase.logger.fatal("published: #{$PUBLISH_TOTAL} dispatched: #{$DISPATCH_TOTAL} online since: #{$DISPATCH_START} current speed: #{(100000 * time_diff / $DISPATCH_COUNTER).round / 100}ms/event or #{($DISPATCH_COUNTER / time_diff).round}events/sec // NOTE: ms/event will be high if idle")
            $DISPATCH_COUNTER = 0
            $DISPATCH_TIME = Time.now
          end
        end
      end
    end

    # Proceeds the Queue of the QueuableSupportListener
    class ProceedSignal < CnsBase::Signal
      attr_accessor :signal
      
      def initialize signal
        super()
        
        @signal = signal
      end
    end
  end
end
