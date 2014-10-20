require 'redisse'
require 'goliath/api'
require 'rack/accept_media_types'
require 'goliath/runner'
require 'em-hiredis'

module Redisse

  # Public: Run the server.
  #
  # If you use the provided binary you don't need to call this method.
  #
  # By default, the {#channels} method is called directly.
  #
  # If {#nginx_internal_url} is set, the channels will actually come from the
  # internal redirect URL generated in the Rack app by {#redirect_endpoint}.
  def run
    run_as_standalone if nginx_internal_url
    server = Server.new(self)
    runner = Goliath::Runner.new(ARGV, server)
    runner.app = Goliath::Rack::Builder.build(self, server)
    runner.load_plugins([Server::Stats] + plugins)
    runner.run
  end

private

  # Internal: Redefine {#channels} to find channels in the redirect URL.
  def run_as_standalone
    channels do |env|
      query_string = env['QUERY_STRING'] || ''
      channels = query_string.split('&').map { |channel|
        URI.decode_www_form_component(channel)
      }
      channels.delete('polling')
      channels.delete_if {|channel| channel.start_with?('lastEventId=') }
    end
  end

  # Internal: Goliath::API class that defines the server.
  #
  # See {Redisse#run}.
  class Server < Goliath::API
    require 'redisse/server/stats'
    include Stats::Endpoint
    require 'redisse/server/responses'
    include Responses
    require 'redisse/server/redis'
    include Redis

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
      return server_stats(env) if server_stats?(env)
      return not_acceptable unless acceptable?(env)
      channels = Array(redisse.channels(env))
      return not_found if channels.empty?
      subscribe(env, channels) or return service_unavailable
      history_events(env, channels)
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

    def subscribe(env, channels)
      return unless pubsub { env.stream_close }
      env.status[:stats][:connected] += 1
      env.logger.debug { "Subscribing to #{channels}" }
      env_sender = -> event { send_event(env, event) }
      pubsub_subcribe(channels, env_sender)
      env['redisse.unsubscribe'.freeze] = -> do
        pubsub_unsubscribe_proc(channels, env_sender)
      end
      true
    end

    def heartbeat(env)
      env['redisse.heartbeat_timer'.freeze] = EM.add_periodic_timer(HEARTBEAT_PERIOD) do
        env.logger.debug "Sending heartbeat".freeze
        env.stream_send(": hb\n".freeze)
      end
    end

    def stop_heartbeat(env)
      return unless timer = env['redisse.heartbeat_timer'.freeze]
      env.logger.debug "Stopping heartbeat".freeze
      timer.cancel
    end

    def unsubscribe(env)
      return unless unsubscribe = env['redisse.unsubscribe'.freeze]
      env['redisse.unsubscribe'.freeze] = nil
      env.logger.debug "Unsubscribing".freeze
      env.status[:stats][:connected] -= 1
      env.status[:stats][:served]    += 1
      unsubscribe.call
    end

    def send_event(env, event, polling = long_polling?(env))
      env.status[:stats][:events] += 1
      env.logger.debug { "Sending:\n#{event.chomp.chomp}" }
      env.stream_send(event)
      return unless polling
      env["redisse.long_polling_timer".freeze] ||= EM.add_timer(LONG_POLLING_DELAY) do
        env.stream_close
      end
    end

    def long_polling?(env)
      key = "redisse.long_polling".freeze
      env.fetch(key) do
        env[key] = Rack::Request.new(env).GET.keys.include?('polling')
      end
    end

    def history_events(env, channels)
      EM::Synchrony.next_tick do
        send_history_events(env, channels)
      end
    end

    def send_history_events(env, channels)
      last_event_id = last_event_id(env)
      events = events_for_channels(channels, last_event_id) if last_event_id
      first = events.first if events
      id = redis_last_event_id unless first
      send_event(env, LAST_EVENT_ID_EVENT % id, false) if id
      return unless first
      if first.start_with?('event: missedevents')
        env.status[:stats][:missing] += 1
      end
      env.logger.debug { "Sending #{events.size} history events" }
      events.each { |event| send_event(env, event) }
    end

    LAST_EVENT_ID_EVENT = ServerSentEvents.server_sent_event(nil,
      type: :lastEventId, id: '%s').freeze

    def redis_last_event_id
      df = redis.get(RedisPublisher::REDISSE_LAST_EVENT_ID)
      EM::Synchrony.sync(df)
    end

    def last_event_id(env)
      last_event_id = env['HTTP_LAST_EVENT_ID'.freeze] ||
        Rack::Request.new(env).GET['lastEventId'.freeze]
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

    def acceptable?(env)
      accept_media_types(env).include? 'text/event-stream'
    end

    def accept_media_types(env)
      key = 'accept_media_types'.freeze
      env.fetch(key) do
        env[key] = Rack::AcceptMediaTypes.new(env['HTTP_ACCEPT'])
      end
    end

  public

    def options_parser(opts, options)
      opts.on '--redis REDIS_URL', 'URL of the Redis connection' do |url|
        redisse.redis_server = url
      end
      default_port = redisse.default_port
      return unless default_port
      options[:port] = default_port
    end

  end
end
