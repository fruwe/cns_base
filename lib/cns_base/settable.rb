module CnsBase
  # Is a listener in the grid, which can dispatch signals to a settable listener
  module Settable
    # Sets the Listener
    class SetListenerTypeSignal < CnsBase::ListenerWrapperSignal
      attr_accessor :rewrite
      
      def initialize listener, rewrite=false
        super listener
        
        @rewrite = rewrite
      end
    end

    # Forwards signals to a preset listener
    class SettableSupportListener < Listener
      attr_accessor :child_listener
      
      def initialize publisher
        super publisher
        
        @child_listener = nil
      end
      
      def dispatch signal
        if signal.is_a?(SetListenerTypeSignal) && (@child_listener.blank? || signal.rewrite)
          CnsBase.logger.debug("SETTABLE: SET TO #{signal.listener.class.name}") if CnsBase.logger.debug?
          @child_listener = signal.listener
          return true
        elsif @child_listener
          CnsBase.logger.debug("SETTABLE: #{signal.class.name} => #{@child_listener.class.name}") if CnsBase.logger.debug?
          return @child_listener.dispatch(signal)
        end
        
        return false
      end
    end
  end
end
