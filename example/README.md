# Redisse example: Rack app

Run the dedicated Redis server:

    $ bin/redis

Run the Rack application server:

    $ rackup --port 8081

Run the SSE server:

    $ bin/sse_server --stdout --verbose

Finally run nginx to glue them together:

    $ nginx -p $PWD -c nginx.conf

Open [http://localhost:8080/](http://localhost:8080/) in multiple browsers and
tabs and then send messages to see them replicated.

A Rack session cookie is used to randomly select one of four channels
(`channel_1` to `channel_4`) and simulate different access rights for
different users of your application.

You can also send events from the command line:

    $ bin/publish global message 'Hello CLI'
