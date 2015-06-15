module TED
  class ObjectHash < Hash
    def each
      super do |key, object|
        next unless key.is_a?(Integer)
        next if object.description.empty?
        yield object
      end
    end
  end
end