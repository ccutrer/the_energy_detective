module TED
  class Spyder
    class Group
      # The Spyder this Group belongs to
      attr_reader :spyder
      # The one-based index of this Group in the entire ECC
      attr_reader :index
      attr_reader :description
      # An Array of CTs[rdoc-ref:CT] that compose this Group
      attr_reader :cts

      def initialize(index, description, cts)
        @index, @description, @cts = index, description, cts
      end

      # Current data for this Group
      def current
        spyder.mtu.ecc.current(:spyders)[self]
      end

      def history(interval: :minutes, offset: nil, limit: nil, date_range: nil, start_time: nil, end_time: nil)
        offset = ECC.send(:interpret_offsets, offset, limit)
        date_range = ECC.send(:interpret_dates, date_range, start_time, end_time)
        spyder.mtu.ecc.send(:history_by_source, self, interval, offset, date_range)
      end

      # :nodoc:
      def inspect
        "#<TED::Spyder::Group:#{index} #{description} cts=#{cts.inspect}>"
      end
    end
  end
end
