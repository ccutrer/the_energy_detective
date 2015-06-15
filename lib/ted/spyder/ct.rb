module TED
  class Spyder
    class CT
      # The Spyder this CT belongs to
      attr_reader :spyder
      attr_reader :multiplier, :description

      def initialize(twenty_amp, multiplier, description)
        @twenty_amp, @multiplier, @description = twenty_amp, multiplier, description
      end

      def twenty_amp?
        @twenty_amp
      end

      # :nodoc:
      def inspect
        "#<TED::Spyder::CT #{description} multiplier=#{multiplier}>"
      end
    end
  end
end
