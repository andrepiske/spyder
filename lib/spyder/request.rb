# frozen_string_literal: true

module Spyder
  class Request
    extend Forwardable

    attr_accessor :verb
    attr_accessor :path
    attr_accessor :headers
    attr_accessor :protocol, :remote_address
    attr_accessor :io

    def_delegators :@headers, :ordered, :dict, :add_header

    def initialize
      @headers = HeaderStore.new(:request)
    end

    def host_with_port
      result = dict['host']&.split(':')
      return nil if result == nil
      result << 443 if result.length < 2
      result
    end

    def host
      h = host_with_port
      return nil if h == nil
      h[0]
    end

    def port
      h = host_with_port
      return nil if h == nil
      h[1]
    end

    def path_info
      separator = path.index '?'
      return path if separator == nil
      path[0...separator]
    end

    def query_string
      separator = path.index '?'
      return nil if separator == nil
      path[separator+1..-1]
    end

    def query_params
      return {} unless query_string
      res = {}
      query_string.split('&').each do |line|
        name, value = line.split('=')
        name = CGI.unescape(name)
        value = CGI.unescape(value)

        if name.end_with?('[]') && name.length > 2
          name = name[..-3]
          arr = res.fetch(name, [])
          arr = (res[name] = [])
          arr << value
        else
          res[name] = value
        end
      end

      res
    end

    def read_full_body
      len = dict['content-length']
      len ? io.read(Integer(len)) : io.read # FIXME:
    end

    def has_body?
      dict['transfer-encoding'] != nil || dict['content-length'] != nil
    end

    def verb_allows_body?
      %w(POST PUT PATCH).include?(verb)
    end
  end
end
