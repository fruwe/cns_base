module CnsBase
  module Cluster
    class ClusterCreationSignal < CnsBase::RequestResponse::RequestSignal
      attr_accessor :core_class
      
      def initialize publisher_or_uuid, core_class, params
        super(publisher_or_uuid, nil, params)
        
        raise "core class can not be nil" if core_class.blank?
        
        @core_class = core_class
      end
    end

    class ClusterCreationSupportListener < CnsBase::Listener
      attr_accessor :cluster_core
      
      def initialize publisher
        super publisher
        
        @cluster_core = nil
      end
      
      def dispatch signal
        if signal.is_a?(ClusterCreationSignal)
          if signal.deferred_response?
      		  @cluster_core.dispatch signal
      		else
            raise "cluster core already set to #{@cluster_core.class.name}" if @cluster_core
          
            CnsBase.logger.debug("ClusterCreationSupportListener: #{signal.core_class.name}") if CnsBase.logger.debug?
    		  
      		  @cluster_core = signal.core_class.new(publisher)
      		  
      		  publisher.instance_variable_set("@core_class", signal.core_class)

      		  signal.priority!

      		  @cluster_core.dispatch signal
    		  end
    		  
    		  signal.response = CnsBase::RequestResponse::ResponseSignal.new unless signal.deferred? || signal.responded?
      		
          return true
        elsif @cluster_core
          return @cluster_core.dispatch(signal)
        else
        end

        return false
      end
    end

    # Is the user defined cluster core. Here is basically most important thing to the user.
    class ClusterCore < CnsBase::Listener
      def initialize publisher
        super publisher
      end
    end

    # Cluster is controller for a cluster core.
    class Cluster < CnsBase::Publisher
      include CnsBase::Filter
      include CnsBase::Settable
      include CnsBase::Provider
      include CnsBase::Routing
      include CnsBase::Queue
      include CnsBase::RequestResponse
      include CnsBase::Timer
      include CnsBase::Address
      include CnsBase::HttpClient

      def self.shutdown
        main_cluster = @main_cluster
        @main_cluster = nil
        
        main_cluster.listener.onoff = false if main_cluster
      end
      
      def self.main_cluster
        @main_cluster ||= nil
        
        if @main_cluster.blank?
          @main_cluster = Cluster.new
          @main_cluster.uri = "/"
        end
        
        @main_cluster
      end
      
      attr_accessor :listener
      
      def initialize
        super
        
        @listener = CnsBase::Queue::QueuableSupportListener.new(self)
        @listener.onoff = true # start automatic mode after init

        @listener.dispatch( SetListenerTypeSignal.new( TimerListener.new( self ) ) )
        @listener.dispatch( SetListenerTypeSignal.new( RequestResponseListener.new( self ) ) )
        @listener.dispatch( SetListenerTypeSignal.new( HttpClientSupportListener.new( self ) ) )
        @listener.dispatch( SetListenerTypeSignal.new( FilterSupportListener.new( self ) ) )
        
        # add a signal provider to the filter
    		@listener.dispatch( 
    		  FilterDirectionSignal.new(
    		    SetListenerTypeSignal.new( 
    		      ProviderSupportListener.new( self ) 
    		    ) 
    		  ) 
    		)
    		
    		# add a signal provider to the listener side of the filter
    		@listener.dispatch( 
    		  ListenerDirectionSignal.new( 
    		    SetListenerTypeSignal.new( 
    		      ProviderSupportListener.new( self ) 
    		    ) 
    		  ) 
    		)
    		
    		# add a cluster creation supporter inside the provider
    		@listener.dispatch( 
    		  ListenerDirectionSignal.new( 
    		    AddListenerSignal.new( 
    		      ClusterCreationSupportListener.new( self )
    		    ) 
    		  ) 
    		)

    		# add a routing support listener
    		@listener.dispatch( 
    		  ListenerDirectionSignal.new( 
    		    AddListenerSignal.new( 
    		      RoutingSupportListener.new( self ) 
    		    ) 
    		  )
    		)
      end
      
      # A publisher can publish signals
      
      def publish signal
        benchmark
        
        CnsBase.logger.debug("#{Cluster.main_cluster == self ? "MAIN " : ""}CLUSTER: #{signal.class.name}") if CnsBase.logger.debug?
        
        # send to address router, if a routed signal
        if signal.is_a?(AddressRouterSignal) && self != Cluster.main_cluster
          Cluster.main_cluster.publish signal
          return
        end
        
        listener.dispatch signal
      end
      
      private
      
      $PUBLISH_MUTEX = Mutex.new
      $PUBLISH_TOTAL = 0
      def benchmark
        $PUBLISH_MUTEX.synchronize do
          $PUBLISH_TOTAL += 1
        end
      end
    end
  end
end
