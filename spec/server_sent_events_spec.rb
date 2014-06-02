require 'spec_helper'
require_relative '../lib/redisse/server_sent_events'

describe Redisse::ServerSentEvents do

  include described_class

  it "outputs a basic Server-Sent Event" do
    expect(server_sent_event('foobar')).
      to match(/\Adata: ?foobar\n\n\z/)
  end

  it "outputs the empty string with nil data" do
    expect(server_sent_event(nil)).
      to match(/\Adata: ?\n\n\z/)
  end

  it "uses data as a String" do
    object = Object.new
    def object.to_s
      "data"
    end
    expect(server_sent_event(object)).
      to match(/\Adata: ?data\n\n\z/)
  end

  it "outputs a Server-Sent Event with type" do
    event = server_sent_event('foo', type: :event_type_foo)
    expect(event).
      to match(/^event: ?event_type_foo$/)
    expect(event).to end_with("\n\n")
  end

  it "outputs a Server-Sent Event with id" do
    event = server_sent_event('foo', id: 12)
    expect(event).
      to match(/^id: ?12$/)
    expect(event).to end_with("\n\n")
  end

  it "outputs a Server-Sent Event with retry" do
    event = server_sent_event('foo', retry: 500)
    expect(event).
      to match(/^retry: ?500$/)
    expect(event).to end_with("\n\n")
  end

  it "outputs a Server-Sent Event with multiple data lines if necessary" do
    expect(server_sent_event("hello\nworld\n!")).
      to match(/\Adata: ?hello\ndata: ?world\ndata: ?!\n\n\z/)
  end

end
