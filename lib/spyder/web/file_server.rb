# frozen_string_literal: true

module Spyder
  module Web
    class FileServer
      attr_reader :base_paths
      attr_reader :default_index

      def initialize(paths, index: nil)
        @default_index = index
        @base_paths = Array(paths).map do |path|
          File.expand_path(File.join(Dir.pwd, path))
        end
      end

      def call(request)
        return unless request.verb == 'GET'

        input_path = request.path
        input_path = @default_index if request.path == '/' && @default_index

        req_path = safe_request_path(input_path)
        full_path = nil
        return unless @base_paths.any? do |base|
          fp = File.join(base, *req_path)
          next unless File.file?(fp)
          full_path = fp

          true
        end

        st = File.readable?(full_path) ? File.stat(full_path) : nil

        return unless st && %w[file link].include?(st.ftype)

        etag = "\"#{"%xT-%x0" % [st.mtime, st.size]}\""

        resp = serve_not_modified_response(request, st, etag)
        return resp if resp

        resp = Spyder::Response.new
        resp.add_standard_headers
        resp.set_header 'last-modified', st.mtime.httpdate
        resp.set_header 'etag', etag
        resp.set_header 'cache-control', 'public, must-revalidate, max-age=0'

        File.open full_path do |fp|
          mime = Marcel::MimeType.for(fp)
          if mime == 'application/octet-stream' || mime == 'text/plain'
            mime = Marcel::MimeType.for(name: req_path.last)
          end

          resp.set_header('content-type', mime) if mime

          fp.rewind
          resp.body = fp.read
        end

        resp
      end

      private

      def serve_not_modified_response(request, st, etag)
        if_etag = request.headers.dict['if-none-match']
        if_modified_since = request.headers.dict['if-modified-since']

        return unless if_etag || if_modified_since

        resp = Spyder::Response.new
        resp.add_standard_headers
        resp.code = 304

        return resp if if_etag && if_etag == etag

        if_ms = if_modified_since ? Time.parse(if_modified_since) : nil

        (if_ms && Time.at(st.mtime.to_i) <= if_ms) ? resp  : nil
      end

      def safe_request_path(path)
        path.split('/').reject do |component|
          component == '..' || component == '' || component == '.'
        end
      end
    end
  end
end
