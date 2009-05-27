# This stub controller is the base for an synchronized access to the cns base framework.
# You can declare functions which get normal parameters and can have a return value.
# Note, though, that all parameters need to be serializable (thus to_yaml must be working)
# Usage:
#
# 1) You have to add the StubControlClusterCoreCore to your cluster configuration somewhere.
# example:
# =>  {:class => CnsBase::Stub::StubControlClusterCore, :uri => "/synq_access_0"}
# 2) You should extend StubAccessSupport to declare your synchronized functions
# example:
# => def divide a, b
#      ... # two things must happen here, an event creation and an event listener must be declared.
#          # exception might be thrown as well (devision by 0 for example)
#    end
module CnsBase
  module Stub
    class StubAccessSupport
      def self.cns_method method_name, params=nil, &block
        self.send :define_method, method_name do |*args|
          p = nil

          if params
            raise "expected params: #{params.inspect}; got #{args.size} params" if args.size != params.size 
          
            p = {}
            params.each_with_index do |n, i|
              p[n] = args[i]
            end
          else
            p = *args
          end
          
          request = create_request StubControlClusterCore.stub.publisher, method_name, p
          
          response = StubControlClusterCore.stub.publish_request_and_wait(request, self.delivery_address)
          
          if block
            on_response request, response, block
          else
            return response
          end
        end
      end
      
      attr_accessor :delivery_address
      
      def initialize delivery_address
        @delivery_address = delivery_address
      end
      
      # overwrite for customized request classes
      def create_request publisher, method, params
        CnsBase::RequestResponse::RequestSignal.new(publisher, method, params)
      end
      
      # overwrite for customized response classes
      def on_response request, response, block
        block.call(response.name, response.params)
      end
    end
    
    class StubControlClusterCore < CnsBase::Cluster::ClusterCore
      def self.stub= stub
        @stub = stub
      end
      
      def self.stub
        @stub ||= nil
        
        @stub
      end
      
      attr_accessor :requests

      def initialize publisher
        super publisher
        
        @requests = {}

        StubControlClusterCore.stub = self

        CnsBase.logger.info("CREATED StubControlClusterCore") if CnsBase.logger.info?
      end

      def publish_request_and_wait signal, delivery_address
        wait_sig = signal
        
        if delivery_address
          signal = CnsBase::Address::AddressRouterSignal.new(
            signal,
            CnsBase::Address::PublisherSignalAddress.new(publisher), 
            CnsBase::Address::URISignalAddress.new(delivery_address)
          )
        end
        
        hash = {:semaphore => Mutex.new, :resource => ConditionVariable.new}

        hash[:semaphore].synchronize do
          @requests[wait_sig.uuid] = hash
          
          publisher.publish signal

          hash[:resource].wait(hash[:semaphore])
        end
        
        raise unless hash[:response]
        
        if hash[:response].is_a?(CnsBase::RequestResponse::ExceptionResponseSignal)
          CnsBase.logger.debug(hash[:response].exception.backtrace.pretty_inspect) if CnsBase.logger.debug?
          raise hash[:response].exception
        end
        
        return hash[:response]
      end
      
      def dispatch signal
        if signal.is_a?(CnsBase::RequestResponse::ResponseSignal)
          hash = @requests.delete signal.request_id

          raise unless hash

          hash[:response] = signal

          hash[:semaphore].synchronize do
            hash[:resource].signal
          end
          
          if signal.is_a?(CnsBase::RequestResponse::ExceptionResponseSignal)
            signal.handled!
          end

          return true
        end
        
        return false
      end
    end
  end
end
