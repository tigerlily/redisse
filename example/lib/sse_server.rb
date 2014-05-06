require 'redisse'

module SSEServer
  extend Redisse

  self.redis_server = 'redis://localhost:6379/'
  self.default_port = 8082

  def self.channels(env)
    %w[ global ]
  end
end
