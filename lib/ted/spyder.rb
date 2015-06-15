require 'ted/spyder/ct'
require 'ted/spyder/group'

module TED
  class Spyder
    # The MTU this Spyder belongs to
    attr_reader :mtu
    # An Array of CTs[rdoc-ref:CT] connected to this Spyder
    attr_reader :cts
    # An Array of Groups[rdoc-ref:Group] defined on this Spyder
    attr_reader :groups

    def initialize(mtu, cts, groups)
      @mtu, @cts, @groups = mtu, cts, groups
    end

    # :nodoc:
    def inspect
      "#<Ted::Spyder>"
    end
  end
end
