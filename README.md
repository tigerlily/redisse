# Redisse

Redisse is a Redis-backed Ruby library for creating [Server-Sent
Events](http://www.w3.org/TR/eventsource/), publishing them from your
application, and serving them to your clients.

SSE allows to type your events and Redisse doesn't use this so you can use it
for your application code, but keep in mind that any client will receive events
for all the different types. To handle access rights, where some users can see
some events, use channels instead.

## Rationale

Redisse’s design comes from these requirements:

* The client wants to listen to several channels but use only one connection.
  (e.g. a single `EventSource` object is created in the browser but you want
  events coming from different Redis channels.)

* A server handles the concurrent connections so that the application servers
  don't need to (e.g. Unicorn workers).

* The application is written in Ruby, so there needs to be a Ruby API to
  publish events.

* The application is written on top of Rack, so the code that lists the Redis
  Pub/Sub channels to subscribe to needs to be able to use Rack middlewares and
  should receive a Rack environment. (e.g. you can use
  [Warden](https://github.com/hassox/warden) as a middleware and simply use
  `env['warden'].user` to decide which channels the user can access.)

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

### Behind nginx

You’ll want to redirect the SSE requests to the SSE server instead of your Rack
application. You should disable buffering (`proxy_buffering off`) and close the
connection to the server when the client disconnects
(`proxy_ignore_client_abort on`) to preserve resources (otherwise connections
to Redis will be kept alive longer than necessary).

You can check the [nginx conf for the
example](https://github.com/tigerlily/redisse/blob/master/example/nginx.conf).

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
