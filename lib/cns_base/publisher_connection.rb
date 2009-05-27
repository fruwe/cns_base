module CnsBase
  # Connects Listener and Publisher
  module PublisherConnection
    # Publishes signal, which are dispatched to the listener
    class PublisherConnectionSupportListener < Listener
      attr_accessor :child_publisher

      def initialize publisher
        super publisher

        @child_publisher = nil
      end

      def dispatch signal
        if signal.is_a?(SetPublisherConnectionSignal)
          @child_publisher = signal.publisher
          return true
        elsif @child_publisher
          # TODO: verify and/or change the place. Problem: signal is supposed to not change
          signal = Marshal.load(Marshal.dump(signal))
          
          @child_publisher.publish signal
          return true
        end
        
        return false
      end
    end
    
    # Sets the publisher of a PublisherConnectionSupportListener
    class SetPublisherConnectionSignal < CnsBase::PublisherWrapperSignal
      def initialize publisher
        super publisher
      end
    end
  end
end
