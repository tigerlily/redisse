require 'redisse'
require 'rack'

module SSEServer
  extend Redisse

  self.redis_server = 'redis://localhost:6379/'
  self.default_port = 8082

  def self.channels(env)
    env['rack.session']['channels'] ||=
      %w[ global ] << "channel_#{rand 2}"
  end

  use Rack::Session::Cookie, secret: 'not a secret'
end
