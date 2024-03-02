# frozen_string_literal: true

module Spyder
  class Response
    attr_reader :code
    attr_accessor :body
    attr_reader :headers
    attr_writer :reason_sentence

    CODE_TO_REASON_SENTENCE = {
      100 => 'Continue',
      101 => 'Switching Protocols',
      200 => 'OK',
      201 => 'Created',
      202 => 'Accepted',
      203 => 'Non-Authoritative Information',
      204 => 'No Content',
      205 => 'Reset Content',
      206 => 'Partial Content',
      300 => 'Multiple Choices',
      301 => 'Moved Permanently',
      302 => 'Found',
      303 => 'See Other',
      304 => 'Not Modified',
      305 => 'Use Proxy',
      307 => 'Temporary Redirect',
      400 => 'Bad Request',
      401 => 'Unauthorized',
      402 => 'Payment Required',
      403 => 'Forbidden',
      404 => 'Not Found',
      405 => 'Method Not Allowed',
      406 => 'Not Acceptable',
      407 => 'Proxy Authentication Required',
      408 => 'Request Timeout',
      409 => 'Conflict',
      410 => 'Gone',
      411 => 'Length Required',
      412 => 'Precondition Failed',
      413 => 'Payload Too Large',
      414 => 'URI Too Long',
      415 => 'Unsupported Media Type',
      416 => 'Range Not Satisfiable',
      417 => 'Expectation Failed',
      418 => 'I\'m a teapot',
      422 => 'Unprocessable Entity',
      426 => 'Upgrade Required',
      500 => 'Internal Server Error',
      501 => 'Not Implemented',
      502 => 'Bad Gateway',
      503 => 'Service Unavailable',
      504 => 'Gateway Timeout',
      505 => 'HTTP Version Not Supported',
    }.freeze

    SYMBOL_TO_CODE = CODE_TO_REASON_SENTENCE.to_a.to_h do |code, name|
      [
        name.downcase.tr(' ', '_').tr("'", '').to_sym,
        code
      ]
    end.freeze

    def initialize
      self.code = :ok
      @headers = HeaderStore.new(:response)
    end

    def add_standard_headers
      set_header 'date', Time.now.httpdate
      set_header 'server', "spyder/#{::Spyder::VERSION}"
    end

    def nocache!
      set_header 'expires', Time.at(0).httpdate
      set_header 'cache-control', 'private, no-store, no-cache'
    end

    def code=(value)
      @code = value.is_a?(Symbol) ? SYMBOL_TO_CODE.fetch(value) : value
    end

    def set_header(key, value)
      @headers.set_header(key, value)
    end

    def reason_sentence
      @reason_sentence || CODE_TO_REASON_SENTENCE[@code]
    end

    def self.make_generic(code, payload=nil)
      new.tap do |r|
        code = SYMBOL_TO_CODE.fetch(code, code)
        r.body = (payload || "#{code} #{CODE_TO_REASON_SENTENCE[code]}")
        r.code = code
        r.add_standard_headers
        r.nocache!
      end
    end
  end
end
