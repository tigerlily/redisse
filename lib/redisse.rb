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
  # Examples
  #
  #   class Events < Redisse
  #     # ...
  #   end
  #   Events.redis_server = "redis://localhost:6379/42"
  attr_accessor :redis_server

  # Public: The default port of the server.
  attr_accessor :default_port

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
  # The Redis keys with the same name as the channels will be used to store an
  # history of the last events sent, in order to support Last-Event-Id.
  #
  # You need to override this method in your subclass, and depending on the
  # Rack environment, return a list of channels the current user has access to.
  #
  # env - The Rack environment for this request.
  #
  # Examples
  #
  #   def channels(env)
  #     %w( comment post )
  #   end
  #
  #   # will result in: SUBSCRIBE comment post
  #
  # Returns an Array of String naming the channels to subscribe to.
  def channels(env)
    raise NotImplementedError, "you must implement #{self}.channels"
  end

  def redis
    @redis ||= Redis.new(url: redis_server)
  end

  def test_mode!
    @publisher = TestPublisher.new
  end

  def test_filter=(filter)
    test_mode!
    publisher.filter = filter
  end

  def published
    fail "Call #{self}.test_mode! first" unless publisher.respond_to?(:published)
    publisher.published
  end

  def middlewares
    @middlewares ||= []
  end

  def use(middleware, *args, &block)
    middlewares << [middleware, args, block]
  end

  def plugin(name, *args)
    plugins << [name, args]
  end

  def plugins
    @plugins ||= []
  end

private

  def publisher
    @publisher ||= RedisPublisher.new(redis)
  end

end
