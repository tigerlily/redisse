require 'spec_system_helper'
require_relative '../example/lib/sse_server'

REDIS_PORT = 6380
SSE_PORT   = 8082

describe "Example" do
  include_context "system"

  describe "basic tests" do
    before :context do
      @redis   = run_server "redis",      REDIS_PORT
      @redisse = run_server "sse_server", SSE_PORT
      @redis.wait_tcp
      @redisse.wait_tcp
    end

    after :context do
      @redis.stop
      @redisse.stop
    end

    it "refuses a connection with 406 without proper Accept header" do
      uri = URI("http://localhost:#{SSE_PORT}/")
      Net::HTTP.start(uri.host, uri.port) do |http|
        request = Net::HTTP::Get.new uri
        response = http.request request
        expect(response.code).to be == "406"
      end
    end

    it "refuses a connection with 404 without channels" do
      uri = URI("http://localhost:#{SSE_PORT}/")
      Net::HTTP.start(uri.host, uri.port) do |http|
        request = Net::HTTP::Get.new uri
        request['Accept'] = 'text/event-stream'
        response = http.request request
        expect(response.code).to be == "404"
      end
    end

    it "receives a message" do
      events = EventReader.new "http://localhost:#{SSE_PORT}/?global"
      expect(events).to be_connected
      run_command "publish global foo bar"
      events.each do |event|
        expect(event.type).to be == 'foo'
        expect(event.data).to be == 'bar'
        events.close
      end
    end

    it "closes the connection after a second with long polling" do
      events = EventReader.new "http://localhost:#{SSE_PORT}/?global&polling"
      expect(events).to be_connected
      run_command "publish global foo bar"
      time = Time.now.to_f
      run_command "publish global foo baz"
      received = nil
      expect {
        begin
          Timeout.timeout(2) do
            received = events.each.to_a
          end
        rescue Timeout::Error
        end
        time = Time.now.to_f
      }.to change { time }.by(a_value_within(0.2).of(1.0))
      expect(received.size).to be == 2
      expect(received.map(&:data)).to be == %w(bar baz)
    end

    it "sends a heartbeat" do
      events = EventReader.new "http://localhost:#{SSE_PORT}/?global"
      expect(events).to be_connected
      expect(events.full_stream).to be_empty
      sleep(16)
      expect(events.full_stream).to match(/^: hb$/)
      events.close
    end
  end

  describe "Redis failures" do
    before :context do
      @redis   = run_server "redis",      REDIS_PORT
      @redisse = run_server "sse_server", SSE_PORT
      @redis.wait_tcp
      @redisse.wait_tcp
    end

    after :context do
      @redis.stop
      @redisse.stop
    end

    it "disconnects then refuses connections with 503" do
      events = EventReader.new "http://localhost:#{SSE_PORT}/?global"
      expect(events).to be_connected
      @redis.stop
      Timeout.timeout(0.1) do
        events.each.to_a
      end
      expect(events).not_to be_connected
      events = EventReader.new "http://localhost:#{SSE_PORT}/?global"
      expect(events).not_to be_connected
      expect(events.response.code).to be == "503"
    end

  end
end
