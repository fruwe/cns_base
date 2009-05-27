module CnsBase
  class Publisher
    attr_accessor :uuid
    attr_accessor :uri
    
    def initialize
      @uuid = CnsBase.uuid
      @uri = nil
    end
    
    def publish signal
      result
    end
  end
end
