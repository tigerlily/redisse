require 'spec_helper'
require 'redisse'

module Events
  extend Redisse
end

describe "Publishing events" do
  context "basic usage" do
    before do
      Events.test_mode!
    end

    it "has no events initially" do
      expect(Events.published.size).to be == 0
    end

    it "keeps the published events" do
      Events.publish :global, foo: 'bar'
      expect(Events.published.size).to be == 1
      Events.publish :global, foo: 'baz'
      expect(Events.published.size).to be == 2
    end

    it "gives access to the event channel, type and data" do
      Events.publish :global, foo: 'bar'
      event = Events.published.first
      expect(event.channel).to be == :global
      expect(event.type).to    be == :foo
      expect(event.data).to    be == 'bar'
    end

    it "parses data as JSON" do
      Events.publish :global, foo: JSON.dump(bar: 'baz')
      json = Events.published.first.json
      expect(json['bar']).to be == 'baz'
    end
  end

  context "with a filter" do
    it "filters by a simple event type" do
      Events.test_filter = :foo
      Events.publish :global, foo: 'bar'
      Events.publish :global, bar: 'bar'
      expect(Events.published.size).to       be == 1
      expect(Events.published.first.type).to be == :foo
    end

    it "filters with a Proc" do
      Events.test_filter = -> type { %i(foo bar).include? type }
      Events.publish :global, foo: 'bar'
      Events.publish :global, bar: 'bar'
      Events.publish :global, baz: 'bar'
      expect(Events.published.size).to be == 2
    end
  end

  it "fails if test mode is not set" do
    events = Module.new.extend Redisse
    expect {
      events.published
    }.to raise_error(/\.test_mode!/)
  end

  describe "TestEvent" do
    require 'yaml'

    class Redisse::TestEvent
      def yml
        YAML.load data
      end
    end

    it "can be extended" do
      Events.test_mode!
      Events.publish :global, foo: YAML.dump(bar: 'baz')
      yml = Events.published.first.yml
      expect(yml[:bar]).to be == 'baz'
    end
  end
end
