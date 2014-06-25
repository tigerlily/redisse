module Redisse
  extend self

  # Public: Define the list of channels to subscribe to.
  #
  # Calls the given block with a Rack environment, the block is expected to
  # return a list of channels the current user has access to. The list is then
  # coerced using +Kernel#Array+.
  #
  # Once the block is defined, other calls will be handled by the block
  # directly, as if the method had been redefined directly. It simply gives a
  # nicer API:
  #
  #   Redisse.channels do |env|
  #   end
  #
  # vs
  #
  #   def Redisse.channels(env)
  #   end
  #
  # block - The block that lists the channels for the given Rack environment.
  #
  # Examples
  #
  #   Redisse.channels do |env|
  #     %w( comment post )
  #   end
  #   # will result in subscriptions to 'comment' and 'post' channels.
  #
  #   Redisse.channels({})
  #   # => ["comment", "post"]
  def self.channels(*, &block)
    if block
      # overwrite method with block
      define_singleton_method :channels, &block
    else
      super
    end
  end

  self.redis_server = ENV['REDISSE_REDIS'] ||
    'redis://localhost:6379/'
  self.default_port = ENV['REDISSE_PORT'] ||
    8080
  self.nginx_internal_url = '/redisse'
end
