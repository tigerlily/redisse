require 'redisse/server_sent_events'

module Redisse
  class RedisPublisher
    include ServerSentEvents

    REDISSE_LAST_EVENT_ID = 'redisse:lastEventId'.freeze
    HISTORY_SIZE = 100

    def initialize(redis)
      @redis = redis or raise 'RedisPublisher needs a Redis client'
    end

    def publish(channel, message, type)
      event_id = @redis.incr(REDISSE_LAST_EVENT_ID)
      event = server_sent_event(message, type: type, id: event_id)
      @redis.publish(channel, event)
      @redis.zadd(channel, event_id, event)
      @redis.zremrangebyrank(channel, 0, -1-HISTORY_SIZE)
      event_id
    end
  end

  class TestPublisher
    def initialize
      @published = []
    end

    Event = Struct.new :channel, :json, :type do
      def message
        JSON.parse(json)
      end
    end

    attr_reader :published

    attr_accessor :filter

    def publish(channel, message, type)
      return if filter && type != filter
      @published << Event.new(channel, message, type)
    end
  end
end
