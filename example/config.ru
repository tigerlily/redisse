require 'bundler/setup'
Bundler.require

$: << __dir__ + '/lib'
require 'sse_server'

class Application
  def call(env)
    request = Rack::Request.new env

    if publish?(request)
      SSEServer.publish(request['channel'], request['message'])
      return Rack::Response.new "No Content", 204
    end

    Rack::Response.new "Not Found", 404
  end

  def publish?(request)
    request.post? && request.path_info == '/publish'
  end
end

use Rack::Static, urls: {"/" => 'index.html'}, root: 'public', index: 'index.html'
run Application.new
