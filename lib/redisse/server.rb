require 'redisse'
require 'goliath/api'
require 'rack/accept_media_types'
require 'goliath/runner'
require 'em-hiredis'

module Redisse

  # Public: Run the server.
  def run
    server = Server.new(self)
    runner = Goliath::Runner.new(ARGV, server)
    runner.app = Goliath::Rack::Builder.build(self, server)
    runner.load_plugins(self.plugins.unshift(Server::Stats))
    runner.run
  end

  class Server < Goliath::API
    require 'redisse/server/stats'

    # Public: Delay between receiving a message and closing the connection.
    #
    # Closing the connection is necessary when using long polling, because the
    # client is not able to read the data before the connection is closed. But
    # instead of closing immediately, we delay a bit closing the connection to
    # give a chance for several messages to be sent in a row.
    LONG_POLLING_DELAY = 1

    # Public: The period between heartbeats in seconds.
    HEARTBEAT_PERIOD = 15

    def initialize(redisse)
      @redisse = redisse
      super()
    end

    def response(env)
      acceptable?(env) or return not_acceptable
      subscribe(env) or return not_found
      heartbeat(env)
      streaming_response(200, {
        'Content-Type' => 'text/event-stream',
        'Cache-Control' => 'no-cache',
        'X-Accel-Buffering' => 'no',
      })
    end

    def on_close(env)
      unsubscribe(env)
      stop_heartbeat(env)
    end

  private

    attr_reader :redisse

    def subscribe(env)
      env.status[:stats]["events.connected".freeze] += 1
      channels = redisse.channels(env)
      return if channels.nil? || channels.empty?
      env['server_sent_events.redis'] = pubsub = connect_pubsub
      send_history_events(env, channels)
      env.logger.debug "Subscribing to #{channels}"
      # Redis supports multiple channels for SUBSCRIBE but not em-hiredis
      channels.each do |channel|
        pubsub.subscribe(channel) { |event| send_event(env, event) }
      end
    end

    def heartbeat(env)
      env['redisse.heartbeat_timer'] = EM.add_periodic_timer(HEARTBEAT_PERIOD) do
        env.logger.debug "Sending heartbeat".freeze
        env.stream_send(": hb\n")
      end
    end

    def stop_heartbeat(env)
      return unless timer = env['redisse.heartbeat_timer']
      env.logger.debug "Stopping heartbeat".freeze
      timer.cancel
    end

    def unsubscribe(env)
      pubsub = env['server_sent_events.redis']
      return unless pubsub
      env.logger.debug "Unsubscribing".freeze
      pubsub.close_connection
    end

    def send_event(env, event)
      env.status[:stats]["events.sent".freeze] += 1
      env.logger.debug { "Sending:\n#{event.chomp.chomp}" }
      env.stream_send(event)
      return unless long_polling?(env)
      env["redisse.long_polling_timer".freeze] ||= EM.add_timer(LONG_POLLING_DELAY) do
        env.stream_close
      end
    end

    def long_polling?(env)
      key = "redisse.long_polling".freeze
      env.fetch(key) do
        query_string = env['QUERY_STRING']
        env[key] = query_string && query_string.include?('polling')
      end
    end

    def send_history_events(env, channels)
      last_event_id = last_event_id(env)
      return unless last_event_id
      EM::Synchrony.next_tick do
        events = events_for_channels(channels, last_event_id)
        env.logger.debug "Sending #{events.size} history events"
        events.each { |event| send_event(env, event) }
      end
    end

    def last_event_id(env)
      regexp = /(?:^|\&)lastEventId=([^\&\n]*)/
      last_event_id = env['HTTP_LAST_EVENT_ID'] ||
        env['QUERY_STRING'] &&
        env['QUERY_STRING'][regexp, 1]
      last_event_id = last_event_id.to_i
      last_event_id.nonzero? && last_event_id
    end

    def events_for_channels(channels, last_event_id)
      events_with_ids = channels.each_with_object([]) { |channel, events|
        channel_events = events_for_channel(channel, last_event_id)
        events.concat(channel_events)
      }.sort_by!(&:last)
      handle_missing_events(events_with_ids, last_event_id)
      events_with_ids.map(&:first)
    end

    def handle_missing_events(events_with_ids, last_event_id)
      first_event, first_event_id = events_with_ids.first
      return unless first_event
      if first_event_id == last_event_id
        events_with_ids.shift
      else
        env.status[:stats]["events.missed".freeze] += 1
        event = ServerSentEvents.server_sent_event(nil, type: :missedevents)
        events_with_ids.unshift([event])
      end
    end

    def events_for_channel(channel, last_event_id)
      df = redis.zrangebyscore(channel, last_event_id, '+inf', 'withscores')
      events_scores = EM::Synchrony.sync(df)
      events_scores.each_slice(2).map do |event, score|
        [event, score.to_i]
      end
    end

    def redis
      @redis ||= EM::Hiredis.connect(redisse.redis_server)
    end

    def connect_pubsub
      client = EM::Hiredis::PubsubClient.new
      client.configure(redisse.redis_server)
      client.connect
    end

    def acceptable?(env)
      accept_media_types = Rack::AcceptMediaTypes.new(env['HTTP_ACCEPT'])
      accept_media_types.include?('text/event-stream')
    end

    def not_acceptable
      [406,
        { 'Content-Type' => 'text/plain' },
        [
          "406 Not Acceptable\n",
          "This resource can only be represented as text/event-stream.\n"]]
    end

    def not_found
      [404,
       { 'Content-Type' => 'text/plain' },
       [ "404 Not Found.\n" ]
      ]
    end

  public

    def options_parser(opts, options)
      default_port = redisse.default_port
      return unless default_port
      options[:port] = default_port
    end

  end
end
