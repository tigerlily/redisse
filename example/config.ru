require 'bundler/setup'

$: << __dir__ + '/lib'
require 'sse_server'

class Application
  def call(env)
    request = Rack::Request.new env

    if publish?(request)
      SSEServer.publish(request['channel'], request['message'])
      return Rack::Response.new "No Content", 204
    elsif subscriptions?(request)
      return Rack::Response.new SSEServer.channels(env).join(", "), 200
    end

    Rack::Response.new "Not Found", 404
  end

  def publish?(request)
    request.post? && request.path_info == '/publish'
  end

  def subscriptions?(request)
    request.get? && request.path_info == '/subscriptions'
  end
end

use Rack::Session::Cookie, secret: 'not a secret'
use Rack::Static, urls: {"/" => 'index.html'}, root: 'public', index: 'index.html'
run Application.new
