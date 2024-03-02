[![Gem Version](https://badge.fury.io/rb/spyder.svg)](https://badge.fury.io/rb/spyder)

# Easy web server

No magic, no DSL bs. Simple, explicit and lightweight.

```ruby
server = Spyder::Server.new('0.0.0.0', 8080)

server.router.add_route 'GET', '/hello-world' do |request, _|
  which_world = request.query_params['world'] || 'Earth'

  resp = Spyder::Response.new
  resp.add_standard_headers
  resp.set_header 'content-type', 'text/plain'
  resp.body = "hello from #{which_world}!"

  resp
end

server.start
```
