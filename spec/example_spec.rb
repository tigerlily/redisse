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

    it "receives a message" do
      events = EventReader.new "http://localhost:#{SSE_PORT}/"
      expect(events).to be_connected
      run_command "publish global foo bar"
      events.each do |event|
        expect(event.type).to be == 'foo'
        expect(event.data).to be == 'bar'
        events.stop
      end
    end
  end
end
