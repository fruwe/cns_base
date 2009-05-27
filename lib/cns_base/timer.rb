module CnsBase
  module Timer
    class TimerListener < Listener
      def self.scheduler
        if @scheduler.blank?
          @scheduler = Rufus::Scheduler.start_new
        
          def scheduler.handle_exception (job, exception)
            puts "job #{job.job_id} caught exception '#{exception}'"
          end
        end
        
        @scheduler
      end
      
      def self.schedule_at time, publisher, signal
        TimerListener.scheduler.at(time, {:publisher => publisher, :signal => signal}, {}) do |job|
          params = job.params
          
          publisher = params[:publisher]
          signal = params[:signal]
          
          publisher.publish signal # queue signal
        end
      end
      
      include CnsBase::Settable

      attr_accessor :listener

      def initialize publisher
        super publisher

        @listener = SettableSupportListener.new publisher
      end
      
      def dispatch signal
        result = false

        if signal.is_a?(TimerSignal)
          TimerListener.schedule_at signal.time, self.publisher, signal.signal
          
          result = true
        else
          result = true if @listener.dispatch signal
        end
        
        return result
      end
    end
    
    class TimerSignal < CnsBase::WrapperSignal
      attr_accessor :time

      def initialize time, signal=nil, name=nil, params=nil
        super(signal, name, params)
        
        if time.is_a?(Time)
          @time = time
        else
          @time = Time.now.to_f + time
        end
      end
    end
  end
end
