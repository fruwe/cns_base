module CnsBase
  module Address
    # is an address of a publisher
    class PublisherSignalAddress
      attr_accessor :publisher_uuid

      def initialize publisher_or_uuid
        @publisher_uuid = publisher_or_uuid.is_a?(Publisher) ? publisher_or_uuid.uuid : publisher_or_uuid
      end
    end

    # uri type of a cluster address
    class URISignalAddress
      attr_accessor :uri

      def initialize uri
        @uri = uri

        raise "uri can not be blank" if uri.blank?
      end
    end
    
    class RoutedSignalAddress
      attr_accessor :group_id

      def initialize group_id
        @group_id = group_id
      end
    end

    # Used for the address router. Used to send a signal from one cluster to another.
    class AddressRouterSignal < CnsBase::SerializedWrapperSignal
      attr_accessor :from
      attr_accessor :to

      def initialize signal, from, to, name=nil, params=nil
        raise if from.blank? || to.blank? || signal.blank?
        raise unless from.is_a?(PublisherSignalAddress)
        
        super(signal, name, params)

        @from = from
        @to = to
      end
    end

    # This listener routes signals between clusters ???
    # TODO: Needs to support multiple clusters
    # TODO: Needs to support forced return events
    class AddressRouterSupportListener < CnsBase::Listener
      include CnsBase::PublisherConnection
      include CnsBase::Routing
      include CnsBase::Provider        

      SERVER = :server
      CLIENTS = :clients

      attr_accessor :publishers

      def initialize publisher
        super publisher

        @publishers = {publisher.uuid => publisher}
      end

      def uri_to_publisher uri
        raise if uri.blank?
        
        @publishers.values.find{|publisher|publisher.uri == uri}
      end

      def dispatch signal
        next unless signal.is_a?(AddressRouterSignal)
        
        begin
          CnsBase.logger.debug("ADDRESS ROUTER: #{signal.class.name}") if CnsBase.logger.debug?

          if signal.to.is_a?(PublisherSignalAddress)
            # if signal in local CAS, publish locally
            @publishers[signal.to.publisher_uuid].publish signal.signal

            return true
          elsif signal.to.is_a?(RoutedSignalAddress)
            routed_signal = RoutedSignal.new(signal.signal, signal.to.group_id)

            @publishers[signal.from.publisher_uuid].publish(routed_signal)

            return true
          elsif signal.to.is_a?(URISignalAddress)
            uri = nil

            if signal.to.uri.starts_with?("/")
              uri = signal.to.uri
            else
              to_uri = signal.to.uri
              
              raise("unsupported uri for address router: #{to_uri}") if to_uri.ends_with?("/") || to_uri == "." || to_uri == ".." || to_uri.include?("*")
            
              from_uri = @publishers[signal.from.publisher_uuid].uri

              uri = []
              uri << from_uri
              uri << "/" unless from_uri == "/"
              uri << to_uri

              uri = uri.join
            end

            CnsBase.logger.debug("ADDRESS ROUTER: to #{uri}") if CnsBase.logger.debug?

            # try direct path
            next_to = uri_to_publisher(uri)

            if next_to
              if signal.signal.is_a?(CnsBase::Cas::RemoveClusterSignal)
                CnsBase.logger.info("REMOVE: #{describer_name}") if CnsBase.logger.info?

                next_to.listener.onoff = false
              
                @publishers.delete next_to.uuid

                raise "not supported yet"
              end

              next_to.publish signal.signal

              return true
            else # unknown cluster (maybe new?)
              if signal.signal.is_a?(CnsBase::Cluster::ClusterCreationSignal)
                CnsBase.logger.info("CREATE #{uri}") if CnsBase.logger.info?

                next_to = CnsBase::Cluster::Cluster.new
              
                @publishers[next_to.uuid] = next_to
                next_to.uri = uri

                from_publisher = @publishers[signal.from.publisher_uuid]

                # add parent to child
                publisher_connection = PublisherConnectionSupportListener.new next_to

                publisher_connection.dispatch(SetPublisherConnectionSignal.new(from_publisher))

                next_to.publish(RoutedSignal.new(AddListenerSignal.new(publisher_connection), SERVER))

                # add child to parent
                publisher_connection = PublisherConnectionSupportListener.new from_publisher

                publisher_connection.dispatch(SetPublisherConnectionSignal.new(next_to))

                from_publisher.publish(RoutedSignal.new(AddListenerSignal.new(publisher_connection), CLIENTS))

                # create core
                next_to.publish signal.signal

                return true
              else
                CnsBase.logger.warn("ADDRESS ROUTER: - UNKNOWN NODE! Can not send #{signal.signal.class.name} to #{uri}") if CnsBase.logger.warn?
                CnsBase.logger.warn("ADDRESS ROUTER: - LIST OF KNOWN NODES: #{@publishers.values.collect{|pub|pub.uri}.inspect}") if CnsBase.logger.warn?

                raise "route to <#{uri}> unknown"
              end
            end
          else
            raise "Unknown Signal Address Type #{signal.to.class.name}"
          end
        rescue(Exception) => exception
          CnsBase::ExceptionSignal.log exception, publisher, signal
        
          publisher.publish exception

          # If signal was a request signal, respond with an exception.
          if signal.signal.is_a?(CnsBase::RequestResponse::RequestSignal)
            exception_signal = CnsBase::RequestResponse::ExceptionResponseSignal.new(exception)
            exception_signal.request_id = signal.signal.uuid

            publisher.publish(
              CnsBase::Address::AddressRouterSignal.new(
                exception_signal, 
                CnsBase::Address::PublisherSignalAddress.new(publisher), 
                CnsBase::Address::PublisherSignalAddress.new(signal.signal.publisher_uuid)
              )
            )
          end

          return true
        end

        return false
      end
    end
  end
end
