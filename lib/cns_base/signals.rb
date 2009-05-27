module CnsBase
  # Common signals, e.g. for exceptions
  
  # Exception signal
  # TODO: Revisit class (is this class necessary?)
  class ExceptionSignal < CnsBase::Signal
    def self.try publisher, signal=nil
      begin
        yield if block_given?
        return true
      rescue(Exception) => exception
        ExceptionSignal.log exception, publisher, signal
        publisher.publish ExceptionSignal.new(exception, signal)
        return false
      end
    end
    
    def self.log exception, publisher=nil, signal=nil
      if CnsBase.logger.warn?
        tmp = []
        
        tmp << "ERROR"
        tmp << "^" * 100
        tmp << "^" * 100
        tmp << "Signal: #{signal.class.name}" if signal
        begin
          tmp << "Signal inspect: #{signal.pretty_inspect}" if signal
        rescue
        end
        tmp << "Publisher: #{publisher.class.name}##{publisher.uuid}(uri: #{publisher.uri})" if publisher
        tmp << "Core: #{publisher.instance_variable_get("@core_class")}" if publisher
        tmp << "#{exception.message}(#{exception.class.name})\n#{(exception.backtrace || [])[0..15].join("\n")}"
        tmp << "v" * 100
        tmp << "v" * 100
        
        CnsBase.logger.warn tmp.join("\n")
      end
    end
    
    attr_accessor :exception
    attr_accessor :signal

    def initialize exception, signal
      super()
      
      @exception = exception
      @signal = signal
    end
  end
  
  # Contains a listener instance
  class ListenerWrapperSignal < CnsBase::Signal
    attr_accessor :listener

    def initialize listener
      super()
      
      @listener = listener
    end
  end

  # Contains a publisher instance
  class PublisherWrapperSignal < CnsBase::Signal
    attr_accessor :publisher

    def initialize publisher
      super()
      
      @publisher = publisher
    end
  end

  # Used for rerouting signals
  class WrapperSignal < CnsBase::Signal
    attr_accessor :signal

    def initialize signal, name=nil, params=nil
      super(name, params)
      
      @signal = signal
    end
  end

  class SerializedWrapperSignal < CnsBase::Signal
    def initialize signal, name=nil, params=nil
      super(name, params)
      
      self.signal = signal
    end
    
    def signal
      if @signal.is_a?(CnsBase::Signal)
        @signal
      else
        Marshal.load(@signal)
      end
    end
    
    def signal= signal
      begin
        @signal = Marshal.dump(signal)
      rescue(Exception) => exception
        if CnsBase.logger.warn?
          CnsBase.logger.warn("WARNING: signal could not be marshaled!!! not save!!!")
          
          if signal.respond_to?(:exception) && signal.exception
            e = signal.exception
            CnsBase.logger.warn("#{e.message}(#{e.class.name})\n#{(e.backtrace || [])[0..15].join("\n")}")
          end
          
          ExceptionSignal.log(exception, nil, signal)
        end
        
        @signal = signal
      end
    end
  end
end
