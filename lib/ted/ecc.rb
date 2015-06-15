require 'base64'
require 'csv'
require 'net/http'

require 'nokogiri'

require 'ted/mtu'
require 'ted/spyder'

module TED
  class ECC
    def initialize(host)
      if host.is_a?(String)
        @host = URI.parse(host)
      else
        @host = host.dup
      end
      @user = @host.user
      @password = @host.password
      @host.user = nil
      @http = Net::HTTP.new(@host.host, @host.port)
      @http.use_ssl = (@host.scheme == 'https')
      @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    # Removes the cached system layout, allowing access to newly defined
    # MTUs[rdoc-ref:#mtus] and Spyders[rdoc-ref:#spyders]
    def refresh
      @mtus = nil
    end

    def current(source = :net)
      params = {}
      params[:T] = 0 # Power

      params[:D] = case source
                     when :net
                       0
                     when :load
                       1
                     when :generation
                       2
                     when MTU
                       params[:M] = source.index
                       255
                     when :spyders
                       return spyders_current
                     else
                       raise ArgumentError, 'source must be :net, :load, :generation, or :spyders'
                   end

      dashboard_data(Nokogiri::XML(query("api/DashData.xml", params)))
    end

    # A hash of the MTUs[rdoc-ref:MTU] connected to this ECC.
    # It is indexed by both description and numerical index
    def mtus
      build_system_layout
      @mtus
    end

    # A hash of the Spyders[rdoc-ref:Spyder::Group] connected to this ECC.
    # It is index by both description and numerical index
    def spyders
      build_system_layout
      @spyders
    end

    # Returns history for all connected MTUs[rdoc-ref:MTU] and Spyders[rdoc-ref:Spyder::Group]
    # The return value is a hash indexed by the MTU or Spyder::Group, and a hash of timestamp,
    # energy or power, and cost
    def history(interval: :seconds)
      raise ArgumentError, "invalid interval" unless INTERVALS.include?(interval)

      params = {}

      params[:T] = INTERVALS.index(interval) + 1

      response = query("history/exportAll.csv", params)
      result = {}
      response.strip!
      CSV.parse(response) do |(channel_name, timestamp, kwh, cost)|
        channel = mtus[channel_name] || spyders[channel_name]
        result[channel] ||= []
        timestamp = case interval
                      when :seconds, :minutes, :hours
                        DateTime.strptime(timestamp, "%m/%d/%Y %H:%M:%S").to_time
                      when :days, :months
                        month, day, year = timestamp.split('/').map(&:to_i)
                        Date.new(year, month, day)
                    end
        energy_key = [:seconds, :minutes].include?(interval) ? :power : :energy
        result[channel] << {
            timestamp: timestamp,
            energy_key => (kwh.to_f * 1000).to_i,
            cost: cost.to_f
        }
      end
      result
    end

    # :nodoc:
    def inspect
      "#<TED::ECC:#{@host}>"
    end

    private

    INTERVALS = [:seconds, :minutes, :hours, :days, :months].freeze
    private_constant :INTERVALS

    def history_by_source(source, interval, offset_range, date_range)
      raise ArgumentError, "invalid interval" unless INTERVALS.include?(interval)


      case source
        when MTU
          source_type = :mtu
        when Spyder::Group
          source_type = :spyder
      end
      raise ArgumentError, "interval cannot be seconds for a Spyder" if source_type == :spyder && interval == :seconds

      params = {}

      params[:D] = (source_type == :mtu ? 0 : 1)
      params[:M] = source.index
      params[:T] = case interval
                     when :seconds
                       1
                     when :minutes
                       2
                     when :hours
                       3
                     when :days
                       4
                     when :months
                       5
                   end
      params[:T] -= 1 if source_type == :spyder

      if offset_range
        if offset_range.end != Float::INFINITY
          params[:C] = offset_range.end + 1
          params[:C] -= 1 if offset_range.exclude_end?
        end
        if offset_range.begin != -Float::INFINITY && offset_range.begin != 0
          raise ArgumentError, "cannot specify an offset for anything besides seconds" unless interval == :seconds
          params[:I] = offset_range.begin
          params[:C] -= params[:I] if params[:C]
        end
      end

      if date_range
        params[:S] = date_range.begin.to_i unless date_range.begin == -Float::INFINITY
        if date_range.end != Float::INFINITY
          end_timestamp = date_range.end.to_i
          end_timestamp -= 1 if date_range.exclude_end?
          params[:E] = end_timestamp
        end
      end

      response = query("history/export.raw", params)
      response.split("\n").map do |line|
        data = Base64.decode64(line)
        bytes = data.unpack('C*')
        raise "Unknown header" unless bytes[0] == 0xa4
        checksum = bytes[0..-2].inject(0, :+) % 256
        raise "Wrong checksum" unless bytes[-1] == checksum
        case source_type
          when :mtu
            case interval
              when :seconds
                _, timestamp, energy, cost, voltage, _ = data.unpack('CL<l<2S<C')
              when :minutes
                _, timestamp, energy, cost, voltage, _pf, _ = data.unpack('CL<l<2S<2C')
              when :hours, :days
                _, timestamp, energy, cost, _ = data.unpack('CL<l<2C')
              when :months
                _, timestamp, energy, cost, _min_charge, _fixed_charge, _demand_charge, _demand_charge_peak_power_average, _demand_charge_time, _demand_charge_tou, _ = data.unpack('CL<l<2L<2l<2L<C2')
            end
          when :spyder
            _, timestamp, energy, cost, _ = data.unpack('CL<l<2C')
        end
        timestamp = Time.at(timestamp)
        timestamp = timestamp.to_date if interval == :days || interval == :months
        cost = cost.to_f / 100
        voltage = voltage.to_f / 10 if voltage
        energy_key = [:seconds, :minutes].include?(interval) ? :power : :energy
        result = { timestamp: timestamp, energy_key => energy, cost: cost }
        result[:voltage] = voltage if voltage
        result
      end
    end

    def spyders_current
      xml = Nokogiri::XML(query('api/SpyderData.xml'))

      result = {}
      net_xml = xml.css("DashData")
      result[:net] = dashboard_data(net_xml)

      xml.css("Group").each_with_index do |group_xml, idx|
        next unless (group = spyders[idx + 1])
        result[group] = dashboard_data(group_xml)
      end

      result
    end

    def build_system_layout
      return if @mtus

      xml = Nokogiri::XML(query("api/SystemSettings.xml"))

      mtus = []
      xml.css("MTU").each do |mtu_xml|
        description = mtu_xml.at_css("MTUDescription").text
        mtus << MTU.new(self, mtus.length, description)
      end

      group_index = 1
      @spyders = {}
      xml.css("Spyder").each do |spyder_xml|
        enabled = spyder_xml.at_css("Enabled").text == '1'
        if !enabled
          group_index += 8
          next
        end

        cts = spyder_xml.css("CT").map do |ct_xml|
          twenty_amp = ct_xml.at_css("Type").text == '1'
          multiplier = ct_xml.at_css("Mult").text.to_i
          multiplier = -(multiplier - 4) if multiplier > 4
          description = ct_xml.at_css("Description").text
          Spyder::CT.new(twenty_amp, multiplier, description)
        end
        groups = []
        spyder_xml.css("Group").each do |group_xml|
          description = group_xml.at_css("Description").text
          ct_mask = group_xml.at_css("UseCT").text.to_i
          group_cts = []
          ct_index = 0
          while ct_mask != 0
            if (ct_mask & 1) == 1
              group_cts << cts[ct_index]
            end
            ct_mask /= 2
            ct_index += 1
          end

          unless group_cts.empty?
            group = Spyder::Group.new(group_index, description, group_cts)
            groups << group
            @spyders[group_index] = @spyders[description] = group
          end
          group_index += 1
        end
        mtu_index = spyder_xml.at_css("MTUParent").text.to_i
        mtu = mtus[mtu_index]
        spyder = Spyder.new(mtu, cts, groups)
        mtu.spyders << spyder
        cts.each { |ct| ct.instance_variable_set(:@spyder, spyder) }
        groups.each { |group| group.instance_variable_set(:@spyder, spyder) }
      end

      @mtus = {}
      mtus.each { |mtu| @mtus[mtu.index] = @mtus[mtu.description] = mtu; mtu.spyders.freeze }
    end

    def query(path, params = nil)
      uri = @host.merge(path)

      uri.query = self.class.hash_to_query(params) if params
      get = Net::HTTP::Get.new(uri)
      get.basic_auth @user, @password if @user
      response = @http.request(get)
      response.body
    end

    def dashboard_data(xml)
      now = xml.at_css('Now').text.to_i
      today = xml.at_css('TDY').text.to_i
      mtd = xml.at_css('MTD').text.to_i
      { now: now, today: today, mtd: mtd }
    end

    def self.hash_to_query(hash)
      hash.map{|k,v| "#{k}=#{v}" }.join("&")
    end

    def self.interpret_offsets(offset, limit)
      return nil unless offset || limit
      if offset.is_a?(Range)
        raise ArgumentError, 'limit cannot be provided if offset is a range' if limit
        return offset
      end
      return offset...(offset + limit) if offset && limit
      return offset...Float::INFINITY if offset
      return 0...limit # if limit
    end

    def self.interpret_dates(date_range, start_time, end_time)
      raise ArgumentError, 'start_time cannot be specified with date_range' if date_range && start_time
      raise ArgumentError, 'end_time cannot be specified with date_range' if date_range && start_time
      return date_range if date_range
      return (start_time && start_time.to_i || -Float::INFINITY)...(end_time && end_time.to_i || Float::INFINITY)
    end
  end
end
