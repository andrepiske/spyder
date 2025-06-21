# frozen_string_literal: true

module Spyder
  class Server
    attr_accessor :router

    def initialize(bind, port, router: Router.new, max_threads: 4, tcp_backlog: 10)
      @server = TCPServer.new(bind, port)
      @tcp_backlog = tcp_backlog
      @max_threads = max_threads
      @middleware = []
      @threads = []
      @tp_sync = Mutex.new
      @router = router
    end

    def add_middleware(callable, args=[])
      @middleware << [callable, args]
    end

    def start
      busy_threads = 0
      @server.listen(@tcp_backlog)

      loop do
        time_start = Process.clock_gettime(:CLOCK_MONOTONIC, :float_second)
        loop do
          current_busy = @tp_sync.synchronize { busy_threads }
          break if current_busy < @max_threads
          sleep(0)
          current_time = Process.clock_gettime(:CLOCK_MONOTONIC, :float_second)
          if (current_time - time_start) > 1.0
            # puts "Waiting a long time: #{(current_time - time_start)}"
            sleep 0.2
          end
        end

        client = @server.accept
        @tp_sync.synchronize { busy_threads += 1 }

        Thread.new do
          begin
            error, response = nil
            begin
              response = process_new_client(client)
            rescue Exception => e
              error = e
            end

            if error
              puts error.full_message

              response = Response.make_generic :internal_server_error
              dispatch_response(client, response)
            end

            if response&.hijack
              response.hijack.call(client)
            else
              client.close rescue nil
            end
          ensure
            @tp_sync.synchronize { busy_threads -= 1 }
          end
        end
      end
    end

    def process_request(request)
      mids = @middleware + [[RouterApp, @router]]
      app = nil
      loop do
        klass, args = mids.pop
        break unless klass
        app = klass.new(args, app)
      end

      app.call({}, request)
    end

    def process_new_client(socket)
      verb, path, protocol = read_line(socket).split(' ')
      request = Request.new
      request.path = path
      request.verb = verb
      request.io = socket

      loop do
        line = read_line(socket)
        break if line == ''
        sep = line.index(':')
        name = line[0...sep].downcase
        value = line[(sep + 2)..]
        request.add_header(name, value)
      end

      response = process_request(request)

      dispatch_response(socket, response)
    end

    def dispatch_response(socket, response)
      content_length = response.headers.dict['content-length']
      if !content_length && response.body && response.body.is_a?(String)
        content_length = response.body.length
        response.set_header 'content-length', content_length.to_s
      end

      response.set_header('connection', 'close') unless response.headers.dict['connection']

      begin
        socket.write("HTTP/1.1 #{response.code} #{response.reason_sentence.b}\r\n")
        response.headers.ordered.each do |name, value|
          socket.write("#{name.b}: #{value.b}\r\n")
        end
        socket.write("\r\n")

        if response.body
          Array(response.body).each do |part|
            content = part.respond_to?(:call) ? part.call : part
            socket.write(content.b)
          end
        end
      rescue Errno::EPIPE
        # socket closed. So what?
        socket.close rescue nil
      end

      response
    end

    def read_line(socket)
      line_limit = 1024 * 16
      buffer = String.new(capacity: 128)
      almost = false
      loop do
        line_limit -= 1
        return false unless line_limit > 0

        c = socket.readchar
        if !almost && c == "\r"
          almost = true
        elsif almost
          return false unless c == "\n"
          return buffer
        else
          buffer += c
        end
      end
    end
  end
end
