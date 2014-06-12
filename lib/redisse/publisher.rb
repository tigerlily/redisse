require 'redisse/server_sent_events'
require 'json'

module Redisse
  # Internal: Publisher that pushes to Redis with history.
  class RedisPublisher
    include ServerSentEvents

    REDISSE_LAST_EVENT_ID = 'redisse:lastEventId'.freeze
    HISTORY_SIZE = 100

    def initialize(redis)
      @redis = redis or raise 'RedisPublisher needs a Redis client'
    end

    def publish(channel, data, type)
      event_id = @redis.incr(REDISSE_LAST_EVENT_ID)
      event = server_sent_event(data, type: type, id: event_id)
      @redis.publish(channel, event)
      @redis.zadd(channel, event_id, event)
      @redis.zremrangebyrank(channel, 0, -1-HISTORY_SIZE)
      event_id
    end
  end

  # Internal: Publisher that stores events in memory for easy testing.
  #
  # See {Redisse#test_mode! Redisse#test_mode!}.
  class TestPublisher
    def initialize
      @published = []
    end

    attr_reader :published

    attr_accessor :filter

    def publish(channel, data, type)
      return if filter && !(filter === type)
      @published << TestEvent.new(channel, data, type)
    end
  end

  # Define then reopen instead of using the block of Struct.new for YARD.
  TestEvent = Struct.new :channel, :data, :type

  # Public: An event in test mode.
  #
  # You can re-open or add modules to this class if you want to add behavior
  # to events found in {Redisse#published Redisse#published} for easier
  # testing.
  #
  # Examples
  #
  #   class Redisse::TestEvent
  #     def yml
  #       YAML.load data
  #     end
  #
  #     def private?
  #       channel.start_with? 'private'
  #     end
  #   end
  class TestEvent
    # Public: Helper method to parse the Event data as JSON.
    def json
      JSON.parse(data)
    end
  end
end
