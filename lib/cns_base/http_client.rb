module CnsBase
  module HttpClient
    # method can be :head, :get, :post, :put, :delete, :options, :propfind, :proppatch, :trace
    # uri is http://www.something.com/hoho
    # query can be hash or an array [[,],[,],...]
    # body can be a string, hash, io or array [[,],[,],...]
    # header can be a hash
    class HttpRequestSignal < CnsBase::RequestResponse::RequestSignal
      attr_accessor :method
      attr_accessor :uri
      attr_accessor :query
      attr_accessor :body
      attr_accessor :header
      
      def initialize publisher_or_uuid, method, uri, query=nil, body=nil, header={}, name=nil, params=nil
        super(publisher_or_uuid, name, params)
        
        raise "unknown method #{method}" unless [:head, :get, :post, :put, :delete, :options, :propfind, :proppatch, :trace].include?(method)
        
        @method = method
        @uri = uri
        @query = query
        @body = body
        @header = header
      end
    end  
    
    # gets a http status and a content
    class HttpResponseSignal < CnsBase::RequestResponse::ResponseSignal
      attr_accessor :status
      attr_accessor :content
      
      def initialize status, content, name=nil, params=nil
        super(name, params)
        
        @status = status
        @content = content
      end
    end
    
    class HttpClientSupportListener < CnsBase::Listener
      attr_accessor :listener
      attr_accessor :requests
      attr_accessor :http_client

      def initialize publisher
        super publisher

        @listener = CnsBase::Settable::SettableSupportListener.new publisher
        @requests = {}
        @http_client = HTTPClient.new
      end
      
      def dispatch signal
        if signal.is_a?(HttpRequestSignal)
          connection = @requests[signal.uuid]
          
          begin
            unless connection
              @requests[signal.uuid] = connection = @http_client.request_async(signal.method, signal.uri, signal.query, signal.body, signal.header)
            end

            if connection.finished?
              @requests.delete signal.uuid
              
              res = connection.pop
            
              signal.response = HttpResponseSignal.new(res.status, res.content.read)
            else
              signal.delay!(publisher, 0.3)
            end
          rescue => exception
            @requests.delete signal.uuid
            
            if signal.deferrers.size > (exception.is_a?(Errno::EMFILE) ? 100 : 10)
              raise exception
            else
              signal.delay!(publisher, 0.3)
            end
          end
          
          return true
        else
          return @listener.dispatch(signal)
        end
      end
    end
  end
end
