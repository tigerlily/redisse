require 'rack/test'

$app, _opts = Rack::Builder.parse_file __dir__ + '/../config.ru'

describe "Example App" do
  include Rack::Test::Methods

  def app
    $app
  end

  describe "/publish" do
    context "basic" do
      before do
        Redisse.test_mode!
      end

      it "publishes the message to the channel" do
        post "/publish", channel: 'global', message: 'Hello'
        expect(Redisse.published.size).to be == 1
        event = Redisse.published.first
        expect(event.channel).to be == 'global'
        expect(event.type).to be == :message
        expect(event.data).to be == 'Hello'
      end
    end

    context "filtered" do
      before do
        Redisse.test_filter = :unused_type
      end

      it "publishes the message with the 'message' type" do
        post "/publish", channel: 'global', message: 'Hello'
        expect(Redisse.published.size).to be == 0
      end
    end
  end
end
