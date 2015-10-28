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

  # Public: Define a custom piece of code to run during a new connection.
  #
  # Calls the given block with a Rack environment.
  #
  # block - The block we want to run at client connection
  #
  # Examples
  #
  #   Redisse.on_connect do |env|
  #     puts "A new client just connected to Redisse"
  #   end
  #
  #   Redisse.on_connect({})
  #   # => "A new client just connected to Redisse"
  def self.on_connect(env, &block)
    if block
      @on_connect = block
    elsif @on_connect
      @on_connect.call(env)
    end
  end

  # Public: Define a custom piece of code to run during a disconnection.
  #
  # Calls the given block with a Rack environment.
  #
  # block - The block we want to run at client disconnection
  #
  # Examples
  #
  #   Redisse.on_disconnect do |env|
  #     puts "A new client just disconnected from Redisse"
  #   end
  #
  #   Redisse.on_disconnect({})
  #   # => "A new client just disconnected from Redisse"
  def self.on_disconnect(env, &block)
    if block
      @on_disconnect = block
    elsif @on_disconnect
      @on_disconnect.call(env)
    end
  end

  self.redis_server = ENV['REDISSE_REDIS'] ||
    'redis://localhost:6379/'
  self.default_port = ENV['REDISSE_PORT'] ||
    8080
  self.nginx_internal_url = '/redisse'
end
