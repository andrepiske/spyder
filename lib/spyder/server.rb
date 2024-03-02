# frozen_string_literal: true

module Spyder
  class Server
    attr_accessor :router

    def initialize(bind, port, router: Router.new, max_threads: 4)
      @server = TCPServer.new(bind, port)
      @max_threads = max_threads
      @middleware = []
      @threads = []
      @tp_sync = Mutex.new
      @router = router
    end

    def add_middleware(callable, args)
      @middleware << [callable, args]
    end

    def start
      @server.listen(10)
      loop do
        client = @server.accept

        app_thread = Thread.new do
          error = nil
          begin
            process_new_client(client)
          rescue Exception => e
            error = e
          end

          if error
            puts error.full_message

            response = Response.make_generic :internal_server_error
            dispatch_response(client, response)
          end

          client.close rescue nil
        end

        over_capacity = true
        added_thread_to_list = false
        while over_capacity
          @tp_sync.synchronize do
            unless added_thread_to_list
              @threads << app_thread
              added_thread_to_list = true
            end
            over_capacity = (@threads.length >= @max_threads)
            # puts("#{@threads.length} of #{@max_threads}")

            @threads.delete_if { |t| !t.alive? }
          end

          # puts("XXX OVER CAPACITY!") if over_capacity
          sleep 0 if over_capacity
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
      end

      socket.write("HTTP/1.1 #{response.code} #{response.reason_sentence.b}\r\n")
      response.headers.ordered.each do |name, value|
        socket.write("#{name.b}: #{value.b}\r\n")
      end
      socket.write("connection: close\r\n") # FIXME:
      socket.write("content-length: #{content_length}\r\n") if content_length
      socket.write("\r\n")

      if response.body
        Array(response.body).each do |part|
          content = part.respond_to?(:call) ? part.call : part
          socket.write(content.b)
        end
      end
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
