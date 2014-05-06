# Redisse example: Rack app

Run the Rack application server:

    $ rackup --port 8081

Run the SSE server:

    $ bin/server --stdout --verbose

Finally run nginx to glue them together:

    $ nginx -p $PWD -c nginx.conf

Open [http://localhost:8080/](http://localhost:8080/) in multiple browsers and
tabs and then send messages to see them replicated.
