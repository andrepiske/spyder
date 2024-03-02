require 'spyder'

server = Spyder::Server.new('0.0.0.0', 8080)

server.router.add_route 'GET', '/hello-world' do |request, _|
  which_world = request.query_params['world'] || 'Earth'

  resp = Spyder::Response.new
  resp.add_standard_headers
  resp.set_header 'content-type', 'text/plain'
  resp.body = "hello from #{which_world}!"

  resp
end

puts "Now navigate to http://localhost:8080/?world=Mars"
server.start
