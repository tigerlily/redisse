module Redisse
  class Server::Stats
    def initialize(address, port, config, status, logger)
      status[:stats] = {

        # Number of stream connections
        connected: 0,

        # Number of events sent
        events:    0,

        # Number of event streams served
        served:    0,

        # Number of missedevents events sent
        missing:   0,

      }
    end

    def run
    end
  end

  module Server::Stats::Endpoint
    def server_stats(env)
      Rack::Response.new JSON_BODY % env.status[:stats], 200, 'Content-Type' => 'application/json'
    end

    def server_stats?(env)
      accept_media_types(env).include? 'application/json'.freeze
    end

    JSON_BODY = <<-EOJSON.strip.freeze
{
  "connected": %<connected>d,
  "events":    %<events>d,
  "served":    %<served>d,
  "missing":   %<missing>d
}
    EOJSON

  end
end
