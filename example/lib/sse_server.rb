require 'redisse'
require 'rack'

module SSEServer
  extend Redisse

  self.redis_server = 'redis://localhost:6380/'
  self.default_port = 8082

  self.nginx_internal_url = '/redisse'

  def self.channels(env)
    env['rack.session']['channels'] ||=
      %w[ global ] << "channel_#{rand(4)+1}"
  end
end
