module CnsBase
  # Is a 1-n provider for signals. One can add and delete listeners to one listener, which will dispatch each
  # signal to all listeners
  module Provider
    # Adds a listener
    class AddListenerSignal < CnsBase::ListenerWrapperSignal
      def initialize listener
        super listener
      end
    end
    
    # broadcasts signals to registered listeners
    class ProviderSupportListener < Listener
      attr_accessor :listener

      def initialize publisher
        super publisher
        
        @listener = []
      end
      
      def dispatch signal
        if signal.is_a?(AddListenerSignal) && signal.listener
          @listener << signal.listener
          return true
        end
        
        if signal.is_a?(RemoveListenerSignal) && signal.listener
          @listener.delete signal.listener
          return true
        end
        
        if signal.is_a?(RemoveListenerSignal) && signal.listener.blank?
          @listener = []
          return true
        end
        
        result = false 
        
        @listener.each do |listener|
          CnsBase.logger.debug("PROVIDER: #{signal.class.name} => #{listener.class.name}") if CnsBase.logger.debug?
          result = true if listener.dispatch signal
        end
        
        result
      end
    end
    
    # Removes a listener
    class RemoveListenerSignal < CnsBase::ListenerWrapperSignal
      def initialize listener
        super listener
      end
    end
  end
end
