# Redisse

Redisse is a Redis-backed Ruby library for creating [Server-Sent
Events](http://www.w3.org/TR/eventsource/), publishing them from your
application, and serving them to your clients.

## Installation

Add this line to your application's Gemfile:

    gem 'redisse', github: 'tigerlily/redisse', tag: 'v0.0.1'

## Usage

Define your SSE server (e.g. in `lib/sse_server.rb`):

    require 'redisse'

    module SSEServer
      extend Redisse

      self.redis_server = 'redis://localhost:6379/'
      self.default_port = 4242

      def self.channels(env)
        %w[ global_events_channel ]
      end
    end

Create a binary to serve it (e.g. in `bin/sse_server`):

    #!/usr/bin/env ruby

    require 'bundler/setup'
    Bundler.require

    require_relative '../lib/sse_server'
    require 'redisse/server'
    SSEServer.run

Run it:

    $ chmod u+x bin/sse_server
    $ bin/sse_server --stdout --verbose

Get ready to receive events:

    $ curl localhost:4242 -H 'Accept: text/event-stream'

Send a Server-Sent Event:

    $ irb -rbundler/setup -Ilib -rsse_server
    > SSEServer.publish('global_events_channel', success: "It's working!")

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
