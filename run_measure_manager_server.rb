require_relative 'measure_manager_server'

port = ARGV[0]
if port.nil?
  port = 1234
end

server = WEBrick::HTTPServer.new(:Port => port)

server.mount "/", MeasureManagerServlet

trap("INT") {
    server.shutdown
}

server.start
