module CnsBase
  # A listener is a signal receiver. Sending signals is also possible
  class Listener
    attr_accessor :publisher

    def initialize publisher
      @publisher = publisher
    end
    
    def dispatch signal
      raise "abstract"
    end
  end
end
