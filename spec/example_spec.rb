require 'spec_system_helper'

describe "Example" do
  include_context "system"

  describe "basic tests" do
    before :context do
      @redis   = run_server "example/bin/redis", REDIS_PORT,   pidfile: 'redis.pid'
      @redisse = run_server "bin/redisse",       REDISSE_PORT
      @redis.wait_tcp
      @redisse.wait_tcp
    end

    after :context do
      @redis.stop if @redis
      @redisse.stop if @redisse
    end

    it "refuses a connection with 406 without proper Accept header" do
      uri = URI redisse_url
      Net::HTTP.start(uri.host, uri.port) do |http|
        response = http.request_get uri
        expect(response.code).to be == "406"
      end
    end

    it "refuses a connection with 404 without channels" do
      reader = EventReader.open redisse_url
      expect(reader).not_to be_connected
      expect(reader.response.code).to be == "404"
    end

    it "returns a Content-Type of text/event-stream" do
      EventReader.open redisse_url(:global) do |reader|
        expect(reader).to be_connected
        expect(reader.response.code).to be == "200"
        expect(reader.response['Content-Type']).to be == 'text/event-stream'
      end
    end

    it "receives a message" do
      reader = EventReader.open redisse_url :global
      expect(reader).to be_connected
      publish :global, :foo, :bar
      reader.each do |event|
        expect(event.type).to be == 'foo'
        expect(event.data).to be == 'bar'
        reader.close
      end
      expect(reader).not_to be_connected
    end

    it "receives different messages on different channels" do
      reader_1 = EventReader.open redisse_url :global, :channel_1
      reader_2 = EventReader.open redisse_url :global, :channel_2
      expect(reader_1).to be_connected
      expect(reader_2).to be_connected
      publish :global,    :foo, :foo_data
      publish :channel_1, :bar, :bar_data
      publish :channel_2, :baz, :baz_data
      events_1 = reader_1.each.take(2)
      events_2 = reader_2.each.take(2)
      expect(events_1.map(&:type)).to be == %w(foo bar)
      expect(events_1.map(&:data)).to be == %w(foo_data bar_data)
      expect(events_2.map(&:type)).to be == %w(foo baz)
      expect(events_2.map(&:data)).to be == %w(foo_data baz_data)
      reader_1.close
      reader_2.close
    end

    describe "long polling" do
      it "keeps the connection open when there's no event", :slow do
        reader = EventReader.open redisse_url :global, :polling
        expect(reader).to be_connected
        received = nil
        begin
          Timeout.timeout(2) do
            received = reader.each.to_a
          end
        rescue Timeout::Error
        end
        expect(reader).to be_connected
        expect(received).to be_nil
        reader.close
      end

      it "closes the connection after a second after an event" do
        reader = EventReader.open redisse_url :global, :polling
        expect(reader).to be_connected
        publish :global, :foo, :bar
        time = Time.now.to_f
        publish :global, :foo, :baz
        received = nil
        expect {
          begin
            Timeout.timeout(2) do
              received = reader.each.to_a
            end
          rescue Timeout::Error
          end
          time = Time.now.to_f
        }.to change { time }.by(a_value_within(0.2).of(1.0))
        expect(reader).not_to be_connected
        expect(received.size).to be == 2
        expect(received.map(&:data)).to be == %w(bar baz)
      end
    end

    it "sends a heartbeat", :slow do
      reader = EventReader.open redisse_url :global
      expect(reader).to be_connected
      sleep(16)
      expect(reader.full_stream).to match(/^: hb$/)
      reader.close
    end

    it "sends history" do
      event_id = publish :global, :foo, :foo_data
      expect(event_id).not_to be_nil
      publish :global,    :foo, :hist_1
      publish :channel_1, :foo, :hist_2
      events = EventReader.open redisse_url(:global, :channel_1), event_id do |reader|
        reader.each.take(2)
      end
      expect(events.map(&:data)).to be == %w(hist_1 hist_2)
    end

    let(:history_size) { 100 }

    describe "sends a missedevents events" do
      example "if full history could not be fetched" do
        event_id = publish :global, :foo, :foo_data
        publish :global, :foo, :missed
        publish :global, :foo, :first
        publish :global, :foo, :foo_data, count: history_size - 2
        publish :global, :foo, :'last straw'
        events = EventReader.open redisse_url(:global), event_id do |reader|
          enum = reader.each
          event = enum.next
          expect(event.type).to be == 'missedevents'
          enum.take(history_size)
        end
        expect(events.first.data).to be == 'first'
        expect(events[1...-1].map(&:data)).to all be == 'foo_data'
        expect(events.last.data).to be == 'last straw'
      end

      example "if full history was fetched but the server can't know if there were missed events" do
        event_id = publish :global, :foo, :foo_data
        publish :global, :foo, :first
        publish :global, :foo, :foo_data, count: history_size - 2
        publish :global, :foo, :'last straw'
        events = EventReader.open redisse_url(:global), event_id do |reader|
          enum = reader.each
          event = enum.next
          expect(event.type).to be == 'missedevents'
          enum.take(history_size)
        end
        expect(events.first.data).to be == 'first'
        expect(events[1...-1].map(&:data)).to all be == 'foo_data'
        expect(events.last.data).to be == 'last straw'
      end
    end

    it "stores 100 events per channel for history" do
      event_id = publish :global, :foo, :seen
      publish :global,    :foo, :foo_data, count: history_size - 1
      publish :channel_1, :bar, :bar_data, count: history_size
      events = EventReader.open redisse_url(:global, :channel_1), event_id do |reader|
        reader.each.take(2 * history_size - 1)
      end
      expect(events.first(history_size - 1).map(&:type)).to all be == 'foo'
      expect(events.last(history_size).map(&:type))     .to all be == 'bar'
    end

    describe "stats" do
      example "have the proper Content-Type" do
        uri = URI redisse_url
        Net::HTTP.start(uri.host, uri.port) do |http|
          response = http.get uri, 'Accept' => 'application/json'
          expect(response['Content-Type']).to be == 'application/json'
        end
      end

      example "have some useful metrics" do
        expect(stats.keys).to match_array %w[connected served events missing]
      end

      example "metrics change properly" do
        expect {
          event_id = publish :global, :foo, :last
          publish :global, :foo, :missed
          publish :global, :foo, :foo_data, count: history_size
          EventReader.open redisse_url(:global), event_id do |reader|
            publish :global, :foo, :bar
            publish :global, :foo, :baz
            publish :global, :foo, :baz
            expect(stats['connected']).to be == 1
            EventReader.open redisse_url(:global) do
              expect(stats['connected']).to be == 2
            end
          end
        }.to change { stats['served']    }.by(2)
        .and change { stats['missing']   }.by(1)
        .and change { stats['connected'] }.by(0)
        .and change { stats['events']    }.by(1 + 1 + history_size + 3)
        # lastEventId + missed + history + 3
      end

      def stats
        uri = URI redisse_url
        Net::HTTP.start(uri.host, uri.port) do |http|
          response = http.get uri, 'Accept' => 'application/json'
          JSON.parse response.body
        end
      end

    end

  end

  describe "Redis failures" do
    before :context do
      @redis   = run_server "example/bin/redis", REDIS_PORT,   pidfile: 'redis.pid'
      @redisse = run_server "bin/redisse",       REDISSE_PORT
      @redis.wait_tcp
      @redisse.wait_tcp
    end

    after :context do
      @redis.stop if @redis
      @redisse.stop if @redisse
    end

    it "disconnects then refuses connections with 503" do
      reader = EventReader.open redisse_url :global
      expect(reader).to be_connected
      @redis.stop
      Timeout.timeout(0.1) do
        reader.each.to_a
      end
      expect(reader).not_to be_connected
      reader = EventReader.open redisse_url :global
      expect(reader).not_to be_connected
      expect(reader.response.code).to be == "503"
    end

  end

  describe "Connection failures" do
    before :context do
      @redis   = run_server "example/bin/redis", REDIS_PORT,   pidfile: 'redis.pid'
      @redisse = run_server "bin/redisse",       REDISSE_PORT
      @redis.wait_tcp
      @redisse.wait_tcp
    end

    after :context do
      @redis.stop if @redis
      @redisse.stop if @redisse
    end

    example "usually result in use of Last-Event-Id" do
      EventReader.open redisse_url :global do |reader|
        expect(reader).to be_connected
        publish :global, :foo, :bar
        expect(reader.each.first).to be
        reader.connection_failure
        expect(reader).not_to be_connected
        publish :global, :foo, :baz
        reader.reconnect
        expect(reader).to be_connected
        event = nil
        Timeout.timeout(0.1) do
          event = reader.each.first
        end
        expect(event.type).to be == 'foo'
        expect(event.data).to be == 'baz'
      end
    end

    example "avoid missed events thanks to the lastEventId event" do
      id = publish :global, :foo, :bar # Redis DB might be completely empty
      EventReader.open redisse_url :global do |reader|
        reader.ensure_last_event_id
        expect(reader.last_event_id).to be == id
        reader.connection_failure
        publish :global, :foo, :baz
        reader.reconnect
        event = nil
        Timeout.timeout(0.1) do
          event = reader.each.first
        end
        expect(event.type).to be == 'foo'
        expect(event.data).to be == 'baz'
      end
    end

  end

  def publish(channel, type, data, count: nil)
    count = "N=#{count}" if count
    output = `#{__dir__}/../example/bin/publish '#{channel}' '#{type}' '#{data}' #{count}`
    output[/(\d+)/, 1]
  end

  def redisse_url(*channels)
    "http://localhost:#{REDISSE_PORT}/?#{URI.encode_www_form(channels)}"
  end
end
