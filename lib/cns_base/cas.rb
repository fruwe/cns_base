module CnsBase
  module Cas
    # Is a cluster, whos publish function has been disabled
    class CasCluster < CnsBase::Cluster::Cluster
      def initialize 
        super
      end
      
      def publish signal
      end
    end

    # The Cluster Application Server. Top Of All Clusters and handels routing of events
    # TODO: Look at the core
    class ClusterApplicationServer < CnsBase::Cluster::ClusterCore
      include CnsBase::Settable
      include CnsBase::Address
      include CnsBase::Cluster
      
      attr_accessor :listener

      def initialize publisher
        super publisher
        
        # Creates a queue with the router as a listener
        @listener = AddressRouterSupportListener.new( publisher )
        
        CnsBase.logger.info("ClusterApplicationServer instance created") if CnsBase.logger.info?
      end
      
      # handels all router signals and initial initialization signal
      def dispatch signal
        CnsBase.logger.debug("CAS: #{signal.class.name}") if CnsBase.logger.debug?

        return listener.dispatch(signal) if signal.is_a?(AddressRouterSignal)
        
        if signal.is_a?(CnsBase::Cluster::ClusterCreationSignal)
          signal.reset_priority
          
          if signal.deferred_response?
            signal.deferrers.each do |h|
              if h[:response].is_a?(CnsBase::RequestResponse::ExceptionResponseSignal)
                CasControlHelper.set_control_helper = :failed
                return
              end
            end
          else
            (signal.params || []).each do |core|
              next if core.is_a?(CasControlHelper)
              raise "ClusterApplicationServer: Illegal Core: #{core.inspect}" unless core.is_a?(Hash) && core.include?(:class) && core.include?(:uri)

              signal.defer! publisher, CnsBase::Address::AddressRouterSignal.new(
                CnsBase::Cluster::ClusterCreationSignal.new(publisher, core[:class], core[:params]),
                CnsBase::Address::PublisherSignalAddress.new(publisher),
                CnsBase::Address::URISignalAddress.new(core[:uri])
              )
            end
          end
          
          unless signal.deferred? || 
            (signal.params || []).each do |helper|
              next unless helper.is_a?(CasControlHelper)
              CasControlHelper.set_control_helper = helper
            end
          end
        end
        
        return false
      end
    end

    # Creates and controlls the CAS
    class CasControlHelper
      include CnsBase::Address
      
      def self.confirm_start
        raise if @cas.blank?
        
        while @cas == :wait
          CnsBase.logger.debug("WAIT FOR CONFIRMED START") if CnsBase.logger.debug?
          sleep 0.1
        end
        
        if @cas == :failed
          CnsBase.logger.fatal("CAS INIT FAILED") if CnsBase.logger.fatal?

          begin
            CasControlHelper.shutdown
          rescue(Exception) => exception
            raise exception 
          end

          raise "CAS INIT FAILED"
        else
          CnsBase.logger.info("CAS INITIALIZED") if CnsBase.logger.info?
        end
        
        @cas
      end
      
      def self.shutdown
        if CnsBase::Cluster::Cluster.main_cluster
          CnsBase::Cluster::Cluster.shutdown
        end

        @cas = nil
      end
      
      def self.init init_hash
        init_hash ||= {}
        
        raise "CAS already started" if @cas
        
        @cas = :wait

        helper = CasControlHelper.new init_hash

        helper.run
        
        CnsBase.logger.info("start cas thread...") if CnsBase.logger.info?
      end
      
      def self.set_control_helper= instance
        @cas = instance
      end
      
      attr_accessor :init_hash
      
      def initialize init_hash
        @init_hash = init_hash
      end
      
      def run
        CnsBase.logger.info("Create CAS...") if CnsBase.logger.info?

        begin
          raise "main cluster can not have an uri" if init_hash.include?(:uri)
          
          publisher = CnsBase::Cluster::Cluster.main_cluster
          
          publisher.publish(CnsBase::Cluster::ClusterCreationSignal.new(publisher, init_hash[:class], ((init_hash[:params] || []) + [self])))
        rescue(Exception)
          CnsBase.logger.fatal("#{$!.inspect}\n#{($@ || []).join("\n")}") if CnsBase.logger.fatal?
          CasControlHelper.set_control_helper = :failed
        end
      end
    end

    class RemoveClusterSignal < CnsBase::Signal
      def initialize
        super()
      end
    end
  end
end
