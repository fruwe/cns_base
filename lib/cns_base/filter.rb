module CnsBase
  # Supports a filter before a listener
  module Filter
    # Routes signals to only to the filter
    class FilterDirectionSignal < CnsBase::WrapperSignal
      def initialize signal
        super signal
      end
    end

    # Dispatches signals to the filter. If true is returned, the signal will be dispatched to the listener
    class FilterSupportListener < Listener
      include CnsBase::Settable

      attr_accessor :filter
      attr_accessor :listener

      def initialize publisher
        super publisher
        
        @filter = SettableSupportListener.new publisher
        @listener = SettableSupportListener.new publisher
      end
      
      def dispatch signal
        CnsBase.logger.debug("filter: #{signal.class.name}") if CnsBase.logger.debug?
        
        if signal.is_a?(FilterDirectionSignal)
          CnsBase.logger.debug("filter: filter(#{filter.child_listener.class.name}) => #{signal.signal.class.name}") if CnsBase.logger.debug?
          filter.dispatch(signal.signal)
        elsif signal.is_a?(ListenerDirectionSignal)
          CnsBase.logger.debug("filter: listener(#{listener.child_listener.class.name}) => #{signal.signal.class.name}") if CnsBase.logger.debug?
          listener.dispatch(signal.signal)
        else
          CnsBase.logger.debug("filter: filter(#{filter.child_listener.class.name}) => #{signal.class.name}") if CnsBase.logger.debug?
          if filter.dispatch(signal)
            CnsBase.logger.debug("filter: filter false") if CnsBase.logger.debug?
            false
          else
            CnsBase.logger.debug("filter: filter ok => listener(#{listener.child_listener.class.name}) => #{signal.class.name}") if CnsBase.logger.debug?
            listener.dispatch(signal)
          end
        end
      end
    end
    
    # Routes signals to only to the listener
    class ListenerDirectionSignal < CnsBase::WrapperSignal
      def initialize signal
        super signal
      end
    end
  end
end
