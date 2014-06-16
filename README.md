# Redisse

Redisse is a Redis-backed Ruby library for creating [Server-Sent
Events](http://www.w3.org/TR/eventsource/), publishing them from your
application, and serving them to your clients.

* **Homepage:**
  [github.com/tigerlily/redisse](https://github.com/tigerlily/redisse)
* **Documentation:**
  [tigerlily.github.io/redisse](https://tigerlily.github.io/redisse/)

## Features

* Pub/Sub split into **channels** for privacy & access rights handling.

* **SSE history** via the `Last-Event-Id` header and the `lastEventId` query
  parameter, with a limit of 100 events per channel.

* **Long-polling** via the `polling` query parameter. Allows to send several
  events at once for long-polling clients by waiting one second before closing
  the connection.

* **Lightweight**: only one Redis connection for history and one for all
  subscriptions, no matter the number of connected clients.

* **`missedevents` event fired** when the full requested history could not be
  found, to allow the client to handle the case where events were missed.

* **Event types** from SSE are left untouched for your application code, but
  keep in mind that a client will receive events of all types from their
  channels. To handle access rights, use channels instead.

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

### Redirect endpoint

The simplest way that last point can be fulfilled is by actually loading and
running your code in the Redisse server. Unfortunately since it’s
EventMachine-based, if your method takes a while to returns the channels, all
the other connected clients will be blocked too. You'll also have some
duplication between your [Rack config](https://github.com/tigerlily/redisse/blob/9052630e57081714365188a8f55f0549aee03d56/example/config.ru#L30)
and [Redisse server config](https://github.com/tigerlily/redisse/blob/9052630e57081714365188a8f55f0549aee03d56/example/lib/sse_server.rb#L15).

Another way if you use nginx is instead to use a endpoint in your main
application that will use the header X-Accel-Redirect to redirect to the
Redisse server, which is now free from your blocking code. The channels will be
sent instead via the redirect URL. See the [section on nginx](#behind-nginx)
for more info.

## Installation

Add this line to your application's Gemfile:

    gem 'redisse', github: 'tigerlily/redisse', tag: 'v0.2.0'

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

Use the endpoint in your main application (in config.ru or your router):

    map "/events" do
      run SSEServer.redirect_endpoint
    end

Run it:

    $ chmod u+x bin/sse_server
    $ bin/sse_server --stdout --verbose

Get ready to receive events:

    $ curl localhost:4242 -H 'Accept: text/event-stream'

Send a Server-Sent Event:

    $ irb -rbundler/setup -Ilib -rsse_server
    > SSEServer.publish('global_events_channel', success: "It's working!")

### Testing

In the traditional Rack app specs or tests, use `Redisse#test_mode!`:

    describe "SSE" do
      before do
        SSEServer.test_mode!
      end

      it "should send a Server-Sent Event" do
        post '/publish', channel: 'global', message: 'Hello'
        expect(SSEServer.published.size).to be == 1
      end
    end

See [the example app
specs](https://github.com/tigerlily/redisse/blob/master/example/spec/app_spec.rb).

### Behind nginx

When running behind nginx as a reverse proxy, you should disable buffering
(`proxy_buffering off`) and close the connection to the server when the client
disconnects (`proxy_ignore_client_abort on`) to preserve resources (otherwise
connections to Redis will be kept alive longer than necessary).

You should take advantage of the [redirect endpoint](#redirect-endpoint)
instead of directing the SSE requests to the SSE server. Let your Rack
application determine the channels, but have the request served by the SSE
server with a redirect (X-Accel-Redirect) to an internal location.

In this case, and if you have a large number of long-named channels, the
internal redirect URL will be long and you might need to increase
`proxy_buffer_size` from its default in your Rack application location
configuration. For example, 8k will allow you about 200 channels with UUIDs as
names, which is quite a lot.

You can check the [nginx conf of the
example](https://github.com/tigerlily/redisse/blob/master/example/nginx.conf)
for all the details.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
