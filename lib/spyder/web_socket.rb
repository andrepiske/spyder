# frozen_string_literal: true

module Spyder
  class WebSocket
    WS_CONST = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

    class Frame
      def initialize
      end

      def decode(raw_data)
        fin = raw_data[0] & 1
        rsv = (raw_data[0] & 0b0111) >> 1
      end
    end

    def initialize
      @socket = nil
      @on_start = nil
      @on_message = nil
      @on_close = nil

      @streaming_buffer = WebSocketStreamingBuffer.new do |frame, mode, fragmented, last_fragment|
        @on_message.call(frame, mode) unless fragmented
      end
      @streaming_buffer.on_close = proc do
        @socket.close rescue nil
      end
    end

    def send_text(data)
      send_data(data, :text)
    end

    def send_binary(data)
      send_data(data, :binary)
    end

    def send_data(data, mode)
      data = data.b

      length = data.length
      buffer = String.new(encoding: 'ascii-8bit', capacity: length + 32)
      buffer += ((1 << 7) | (mode == :binary ? 2 : 1)).chr
      if length < 126
        buffer += length.chr
      elsif length <= 0xFFFF
        buffer += [126, length].pack('CS>')
      else
        buffer += [127, length].pack('CQ>')
      end

      @socket.write(buffer)
      @socket.write(data)
    end

    def on_close(&blk)
      @on_close = blk
    end

    def on_message(&blk)
      @on_message = blk
    end

    def on_start(&blk)
      @on_start = blk
    end

    def hijacked!(socket)
      @socket = socket
      puts "websocket hijacked! #{socket}"
      @thread = Thread.start do
        self.threaded_start!
      end
    end

    def self.upgrade_websocket_request(request)
      ws_key = request.headers.dict['sec-websocket-key']
      return unless ws_key && request.headers.dict['upgrade'] == 'websocket'

      conns = request.headers.dict.fetch('connection', '').split(' ').map(&:strip)
      return unless conns.include?('Upgrade')

      ws_version = request.headers.dict['sec-websocket-version'] # expect: 13
      return unless ws_version

      protocols = request.headers.dict['sec-websocket-protocol']
      protocols = protocols.split(',').map(&:strip) if protocols

      extensions = request.headers.dict['sec-websocket-extensions']
      extensions = extensions.split(';').map(&:strip) if extensions

      decoded_key = Base64.strict_decode64(ws_key) rescue nil
      return unless decoded_key&.length == 16

      response_key = Base64.strict_encode64(
        OpenSSL::Digest::SHA1.digest("#{ws_key}#{WS_CONST}")
      )

      ws = new

      chosen_proto = yield(ws, protocols) if (block_given? && protocols)
      chosen_proto = protocols.first if !chosen_proto && protocols

      resp = Spyder::Response.new(code: 101)
      resp.add_standard_headers
      resp.set_header 'connection', 'Upgrade'
      resp.set_header 'upgrade', 'websocket'
      resp.set_header('sec-websocket-protocol', chosen_proto) if chosen_proto
      resp.set_header 'sec-websocket-accept', response_key

      resp.hijack = proc { |client_socket| ws.hijacked!(client_socket) }

      [resp, ws]
    end

    def threaded_start!
      @on_start.call if @on_start

      while !@socket.closed? && !@socket.eof?
        data = nil
        begin
          data = @socket.read_nonblock(16 * 1024)
        rescue IO::WaitReadable
          IO.select([@socket], [], [@socket])
        end

        next unless data

        puts "ws: read #{data.length} bytes"
        @streaming_buffer.feed(data)
      end

      @on_close.call unless @on_close
    end
  end
end
