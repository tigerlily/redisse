module Redisse
  module Server::Redis
    def redis
      @redis ||= EM::Hiredis.connect(redisse.redis_server)
    end

    def pubsub(&on_disconnected)
      ensure_pubsub
      return false unless @pubsub.connected?
      @pubsub_errbacks << on_disconnected
      true
    end

    def ensure_pubsub
      return if defined? @pubsub
      @pubsub = redis.pubsub
      @pubsub_errbacks = []
      @pubsub.on(:disconnected, &method(:on_redis_close))
      EM::Synchrony.sync(@pubsub)
    end

    def on_redis_close
      @pubsub_errbacks.each(&:call)
      @pubsub_errbacks.clear
    end

    def pubsub_subcribe(channels, callback)
      channels.each do |channel|
        @pubsub.subscribe(channel, callback)
      end
    end

    def pubsub_unsubscribe_proc(channels, callback)
      channels.each do |channel|
        @pubsub.unsubscribe_proc(channel, callback)
      end
    end
  end
end
