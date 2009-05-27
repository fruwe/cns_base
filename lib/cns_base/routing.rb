module CnsBase
  # Routes signals
  module Routing
    # Routes a signal
    class RoutedSignal < CnsBase::WrapperSignal
      PUBLISH_HERE = :here
      
      attr_accessor :group_id
      
      # now this one has different constructors
      def initialize signal, group_id = PUBLISH_HERE
        super signal
      
        @group_id = group_id
      end
    end
    
    # A listener for routing signals to other nodes
    class RoutingSupportListener < Listener
      include CnsBase::Provider
      include CnsBase::PublisherConnection
      
      PUBLISH_HERE = RoutedSignal::PUBLISH_HERE
      
      attr_accessor :connections
      
      def initialize publisher
        super publisher
        
        @connections = {}
        
        publish_here = PublisherConnectionSupportListener.new publisher

        publish_here.dispatch( 
          SetPublisherConnectionSignal.new( 
            publisher 
          )
        )
        
        @connections[PUBLISH_HERE] = publish_here
      end
      
      def dispatch signal
        if signal.is_a?(RoutedSignal)
          group_id = signal.group_id
          listener = connections[group_id]
          
          if listener.blank?
            listener = ProviderSupportListener.new publisher
            @connections[group_id] = listener
          end
          
          CnsBase.logger.debug(("ROUTER: Forward signal #{signal.signal.class.name} to #{group_id}")) if CnsBase.logger.debug?
          
          raise if signal.signal.is_a?(CnsBase::RequestResponse::RequestSignal)
          
          listener.dispatch signal.signal
        end
        
        return false
      end
    end
  end
end
