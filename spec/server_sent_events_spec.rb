require 'spec_helper'
require_relative '../lib/server_sent_events'

describe ServerSentEvents do

  include described_class

  it "outputs a basic Server-Sent Event" do
    expect(server_sent_event('foobar')).
      to match(/\Adata: ?foobar\n\n\z/)
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
