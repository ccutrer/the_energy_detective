module TED
  class MTU
    # The ECC this MTU belongs to
    attr_reader :ecc

    # The 0-based index of this MTU in the ECC
    attr_reader :index

    attr_reader :description

    # An Array of Spyders[rdoc-ref:Spyder] connected to this MTU
    attr_reader :spyders

    def initialize(ecc, index, description)
      @ecc, @index, @description, @spyders = ecc, index, description, []
    end

    def current
      ecc.current(self)
    end

    def history(interval: :seconds, offset: nil, limit: nil, date_range: nil, start_time: nil, end_time: nil)
      offset = ECC.send(:interpret_offsets, offset, limit)
      date_range = ECC.send(:interpret_dates, date_range, start_time, end_time)
      ecc.send(:history_by_source, self, interval, offset, date_range)
    end

    # :nodoc:
    def inspect
      "#<TED::MTU:#{index} #{description}>"
    end
  end
end