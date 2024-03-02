# frozen_string_literal: true
module Spyder
  class HeaderStore
    class MissingHeaderError < ::Spyder::BaseError
    end

    # headers as they have been received. Untransformed and in order
    attr_reader :ordered

    # headers, indexed. All keys are lower case
    attr_reader :dict

    # either :request or :response
    attr_accessor :kind

    def initialize kind=nil
      @kind = kind
      @ordered = []
      @dict = {}
    end

    def fetch key, default_value=nil
      value = @dict.fetch(key.downcase, default_value)
      return value unless value == nil
      return yield(key) if block_given?
      nil
    end

    def get! key
      value = fetch key
      raise MissingHeaderError.new(key) if value == nil
      value
    end

    def add_header key, value
      @ordered << [key, value]
      @dict[key.downcase] = value
    end

    def set_header key, value
      key_lower = key.downcase
      if @kind == :response && key_lower == 'set-cookie'
        add_header key_lower, value
      else
        @dict[key_lower] = value
        oh_index = @ordered.find_index { |k, v| k.downcase == key_lower }
        if oh_index
          @ordered[oh_index][1] = value
        else
          @ordered << [key, value]
        end
      end
    end
  end
end
