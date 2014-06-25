require 'redisse/version'
require 'redisse/publisher'
require 'redis'

# Public: A HTTP API to serve Server-Sent Events via a Redis backend.
module Redisse
  # Public: Gets/Sets the String URL of the Redis server to connect to.
  #
  # Note that while the Redis pubsub mechanism works outside of the Redis key
  # namespace and ignores the database (the path part of the URL), the
  # database will still be used to store an history of the events sent to
  # support Last-Event-Id.
  #
  # Defaults to the REDISSE_REDIS environment variable and if it is not set, to
  # redis://localhost:6379/.
  attr_accessor :redis_server

  # Public: The port on which the server listens.
  #
  # Defaults to the REDISSE_PORT environment variable and if it is not set, to
  # 8080.
  attr_accessor :default_port

  # Public: The internal URL hierarchy to redirect to with X-Accel-Redirect.
  #
  # When this property is set, Redisse will work totally differently. Your Ruby
  # code will not be loaded by the events server itself, but only by the
  # {#redirect_endpoint} Rack app that you will have to route to in your Rack
  # app (e.g. using +map+ in +config.ru+) and this endpoint will redirect to
  # this internal URL hierarchy.
  #
  # Defaults to /redisse.
  attr_accessor :nginx_internal_url

  # Public: Send an event to subscribers, of the given type.
  #
  # All browsers subscribing to the events server will receive a Server-Sent
  # Event of the chosen type.
  #
  # channel      - The channel to publish the message to.
  # type_message - The type of the event and the content of the message, as a
  #                Hash of form { type => message } or simply the message as
  #                a String, for the default event type :message.
  #
  # Examples
  #
  #   Redisse.publish(:global, notice: 'This is a server-sent event.')
  #   Redisse.publish(:global, 'Hello, World!')
  #
  #   # on the browser side:
  #   var source = new EventSource(eventsURL);
  #   source.addEventListener('notice', function(e) {
  #     console.log(e.data) // logs 'This is a server-sent event.'
  #   }, false)
  #   source.addEventListener('message', function(e) {
  #     console.log(e.data) // logs 'Hello, World!'
  #   }, false)
  def publish(channel, message)
    type, message = Hash(message).first if message.respond_to?(:to_h)
    type ||= :message
    publisher.publish(channel, message, type)
  end

  # Public: The list of channels to subscribe to.
  #
  # Once {Redisse.channels} has been called, the given block is this method.
  # The block must satisfy this interface:
  #
  # env - The Rack environment for this request.
  #
  # Returns an Array of String naming the channels to subscribe to.
  #
  # Raises NotImplementedError unless {Redisse.channels} has been called.
  def channels(env)
    raise NotImplementedError, "you must call Redisse.channels first"
  end

  # Public: Use test mode.
  #
  # Instead of actually publishing to Redis, events will be stored in
  # {#published} to use for tests.
  #
  # Must be called before each test in order for published events to be
  # emptied.
  #
  # See also {#test_filter=}.
  #
  # Examples
  #
  #   # RSpec
  #   before { Redisse.test_mode! }
  def test_mode!
    @publisher = TestPublisher.new
  end

  # Public: Filter events stored in test mode.
  #
  # If set, only events whose type match with the filter are stored in
  # {#published}. A filter matches by using case equality, which allows using
  # a simple Symbol or a Proc for more advanced filters:
  #
  # Automatically sets {#test_mode!}, so it also clears the previous events.
  #
  # Examples
  #
  #   Redisse.test_filter = -> type { %i(foo baz).include? type }
  #   Redisse.publish :global, foo: 'stored'
  #   Redisse.publish :global, bar: 'skipped'
  #   Redisse.publish :global, baz: 'stored'
  #   Redisse.published.size # => 2
  def test_filter=(filter)
    test_mode!
    publisher.filter = filter
  end

  # Public: Returns the published events.
  #
  # Fails unless {#test_mode!} is set.
  def published
    fail "Call #{self}.test_mode! first" unless publisher.respond_to?(:published)
    publisher.published
  end

  # Internal: List of middlewares defined with {#use}.
  #
  # Used by Goliath to build the server.
  def middlewares
    @middlewares ||= []
  end

  # Public: Define a middleware for the server.
  #
  # See {https://github.com/postrank-labs/goliath/wiki/Middleware Goliath middlewares}.
  #
  # Examples
  #
  #    Redisse.use MyMiddleware, foo: true
  def use(middleware, *args, &block)
    middlewares << [middleware, args, block]
  end

  # Public: Define a Goliath plugin to run with the server.
  #
  # See {https://github.com/postrank-labs/goliath/wiki/Plugins Goliath plugins}.
  def plugin(name, *args)
    plugins << [name, args]
  end

  # Public: The Rack application that redirects to {#nginx_internal_url}.
  #
  # If you set {#nginx_internal_url}, you need to call this Rack application
  # to redirect to the Redisse server.
  #
  # Also note that when using the redirect endpoint, two channel names are
  # reserved, and cannot be used: +polling+ and +lastEventId+.
  #
  # Examples
  #
  #    map "/events" { run Redisse.redirect_endpoint }
  def redirect_endpoint
    @redirect_endpoint ||= RedirectEndpoint.new self
  end

  autoload :RedirectEndpoint, __dir__ + '/redisse/redirect_endpoint'

private

  def plugins
    @plugins ||= []
  end

  def publisher
    @publisher ||= RedisPublisher.new(redis)
  end

  def redis
    @redis ||= Redis.new(url: redis_server)
  end
end

require 'redisse/configuration'
