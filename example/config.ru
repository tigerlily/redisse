require 'bundler/setup'
require 'dotenv'
Dotenv.load

require 'redisse'

Redisse.channels do |env|
  env['rack.session']['channels'] ||=
    %w[ global ] << "channel_#{rand(4)+1}"
end

class Application
  def call(env)
    request = Rack::Request.new env

    if publish?(request)
      Redisse.publish(request['channel'], request['message'])
      return Rack::Response.new "No Content", 204
    elsif subscriptions?(request)
      return Rack::Response.new Redisse.channels(env).join(", "), 200
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
map "/events" do
  run Redisse.redirect_endpoint
end
run Application.new
