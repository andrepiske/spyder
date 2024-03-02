# frozen_string_literal: true

module Spyder
  class Router
    attr_accessor :fallback_route

    def initialize
      @routes = Hash.new { |k, v| k[v] = [] }
    end

    def add_route(verb, matcher, &handler)
      matcher = Mustermann.new(matcher) if matcher.is_a?(String)

      @routes[verb.to_s.upcase] << [matcher, handler]
    end

    def call(ctx, request)
      only_path = request.path_info

      handler, match_data = nil
      @routes[request.verb].any? do |mt, h|
        md = mt.match(only_path)
        if md
          handler = h
          match_data = md
        end
      end

      match_data ? handler.call(request, match_data) : Response.make_generic(:not_found)
    end
  end

  class RouterApp
    def initialize(router, _)
      @router = router
    end

    def call(ctx, request)
      @router.call(ctx, request)
    end
  end
end
