require 'redisse'
require 'rack'

module SSEServer
  extend Redisse

  self.redis_server = ENV['REDISSE_REDIS']
  self.default_port = ENV['REDISSE_PORT']

  self.nginx_internal_url = '/redisse'

  def self.channels(env)
    env['rack.session']['channels'] ||=
      %w[ global ] << "channel_#{rand(4)+1}"
  end
end
