# Redisse example: Rack app

Get the dependencies:

    $ bundle

Note that the example uses [dotenv](https://github.com/bkeepers/dotenv):

    $ cat .env

Change .env to point to a running Redis server, or simply run the dedicated
Redis server:

    $ bin/redis

Run the Rack application server:

    $ bundle exec dotenv rackup --port 8081

Run the SSE server:

    $ bundle exec dotenv redisse --stdout --verbose

Finally run nginx to glue them together:

    $ nginx -p $PWD -c nginx.conf

Open [http://localhost:8080/](http://localhost:8080/) in multiple browsers and
tabs and then send messages to see them replicated.

A Rack session cookie is used to randomly select one of four channels
(`channel_1` to `channel_4`) and simulate different access rights for
different users of your application.

You can also send events from the command line:

    $ bin/publish global message 'Hello CLI'
