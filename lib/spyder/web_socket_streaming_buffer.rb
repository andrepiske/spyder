# frozen_string_literal: true

module Spyder
  class WebSocketStreamingBuffer
    attr_reader :buffer
    attr_accessor :on_close

    def initialize(&frame_callback)
      @frame_callback = frame_callback
      @on_close = nil
      @buffer = []
      _reset
    end

    def feed(buf)
      @buffer += buf.bytes

      # printable = buf.bytes.map{ |x| x.to_s(16).rjust(2, '0').upcase }.join(' ')
      # puts "Got #{buf.bytes.length} more bytes: [#{printable}]"

      iterations = 0
      loop do
        _flush

        iterations += 1
        if iterations > 1_000
          raise "Watchdog error: got stuck on a loop of #{iterations} iterations."
        end

        break if (@buffer.length == 0 && !@need_buffer_length) ||
          (@need_buffer_length && @buffer.length < @need_buffer_length)
      end
    end

    private

    def _reset
      @state = :initial
      @mask = nil
      @opcode = nil
      @data_mode = nil
      @payload_length = nil
      @need_buffer_length = nil
      @flag_fin = nil
      @fragmented = false
      @fragmented_total_size = nil
    end

    def _flush
      send(:"_flush_#{@state}")
    end

    def _flush_data
      return unless @buffer.length >= @payload_length

      data = if @mask
        (0...@payload_length).map do |i|
          @buffer[i] ^ @mask[i & 3]
        end
      else
        @buffer[0...@payload_length]
      end

      last_fragment = @fragmented && @flag_fin
      @frame_callback.call(data, @data_mode, @fragmented, last_fragment)

      @buffer.shift(@payload_length)

      if @fragmented && !last_fragment
        @need_buffer_length = 2
        @opcode = nil
        @payload_length = nil
        @state = "initial"
      else
        _reset
      end
    end

    def close_with_error(msg)
      @socket.close rescue nil

      puts "Closing websocket: #{msg}"

      @on_close.call if @on_close

      _reset

      @state = :closed
      @socket = nil
      @buffer = nil
    end

    def _flush_readhdr
      return unless @buffer.length >= @need_buffer_length

      @flag_fin = ((@buffer[0] & 0x80) != 0)
      @opcode = (@buffer[0] & 0xF)
      data_len = (@buffer[1] & 0x7F)
      mask_flag = ((@buffer[1] & 0x80) != 0)

      is_control_frame = ((@opcode & 8) != 0)
      if is_control_frame && (data_len > 125 || !@flag_fin)
        # Control frames must not be fragmented and must be <= 125 bytes in size
        return close_with_error("Control frame invalid state")
      end

      if @fragmented && !is_control_frame && @opcode != 0
        # We're in the middle of a fragmented frame and received a non-control
        # frame. That's an error.
        return close_with_error("Got non-control frame during fragmented frame.")
      end

      if !@fragmented && !@flag_fin && !is_control_frame
        @fragmented = true
        @fragmented_total_size = 0
      end

      shift_length = 2

      @payload_length = if data_len == 127
        shift_length += 8
        @buffer[2...10].pack('C*').unpack('Q>').first
      elsif data_len == 126
        shift_length += 2
        @buffer[2...4].pack('C*').unpack('S>').first
      else
        shift_length += 0
        data_len
      end

      if mask_flag
        @mask = @buffer[shift_length...(shift_length + 4)].pack('C*').bytes
        shift_length += 4
      else
        @mask = nil
      end

      @fragmented_total_size += @payload_length if @fragmented

      fgr = nil
      fgr = ", fgr=#{@fragmented_total_size}" if @fragmented
      puts "frame(code=#{@opcode}, len=#{@payload_length}, fin=#{@flag_fin}#{fgr})"

      @buffer.shift(shift_length)
      @need_buffer_length = ((0..2) === @opcode ? @payload_length : nil)

      case @opcode
      when 0x0 # continuation
        @state = "data"
      when 0x1 # text frame
        @state = "data"
        @data_mode = :text
      when 0x2 # binary frame
        @state = "data"
        @data_mode = :binary
      when (0x3..0x7) # reserved
        unexpected_opcode(@opcode)
      when 0x8 # connection close
        @on_close.call if @on_close

        _reset
      when 0x9 # ping
        # TODO: send pong?
      when 0xA # pong
        puts "WS: got pong!"

        _reset
      else
        unexpected_opcode(@opcode)
      end
    end

    def _flush_initial
      return unless @buffer.length >= 2

      data_len = (@buffer[1] & 0x7F)
      mask_flag = (@buffer[1] & 0x80)

      @need_buffer_length = 2 + (mask_flag ? 4 : 0) + (
        data_len == 127 ? 8 : (data_len == 126 ? 2 : 0)
      )

      @state = "readhdr"
      _flush
    end

    def unexpected_opcode opcode
      puts "WS: unexpected opcode #{opcode}"
      exit 1
    end
  end
end
