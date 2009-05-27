module CnsBase
  # A signal, much like an event. The envelope can contain routing information
  class Signal
    attr_accessor :params
    attr_accessor :name
    
    def initialize name=nil, params=nil
      @name = name
      @params = params
      
      raise "name needs to be symbol, string or nil, was #{name.inspect}" unless name == nil || name.is_a?(String) || name.is_a?(Symbol)
      raise "params needs to be hash, array or nil, was #{params.inspect}" unless params == nil || params.is_a?(Hash) || params.is_a?(Array)
    end
    
    def params
      @params ||= {}
      @params
    end
    
    def [] param
      params[param]
    end
    
    def name
      @name || self.class.name
    end
    
    def to_s
      hash = {}
      
      self.instance_variables.each do |a|
        tmp = self.instance_variable_get(a)
        
        hash[a] = tmp.is_a?(Signal) ? tmp.to_s : tmp
      end
      
      p = hash.collect{|name, val|"\t\t#{name}: #{val}\n"}.join
      
      "#{self.class.name}\n#{p}"
    end
  end
end
