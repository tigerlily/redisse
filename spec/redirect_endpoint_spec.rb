require 'spec_helper'
require 'redisse'
require 'rack/test'

describe "Redirect endpoint" do
  include Rack::Test::Methods

  let :redisse do
    Module.new do
      extend Redisse

      def self.channels(env)
        %w(global)
      end

      self.nginx_internal_url = '/internal'
    end
  end

  def app
    redirect_endpoint = redisse.redirect_endpoint
    Rack::Builder.new do
      use Rack::Lint
      run redirect_endpoint
    end
  end

  it "is a Rack app" do
    expect(redisse.redirect_endpoint).to respond_to(:call)
  end

  it "returns a 200 OK" do
    get '/'
    expect(last_response).to be_ok
  end

  def redirect_url(uri = '/')
    get uri
    last_response['X-Accel-Redirect']
  end

  it "redirects to the nginx_internal_url" do
    redisse.nginx_internal_url = '/foo/'
    expect(redirect_url).to start_with "/foo/"
  end

  it "forces a slash at the end" do
    redisse.nginx_internal_url = '/foo'
    expect(redirect_url).to start_with "/foo/"
  end

  def redirect_params(uri = '/')
    query = redirect_url(uri).split('?', 2).last
    URI.decode_www_form(query)
  end

  describe "passing channels" do
    it "passes the channels as query params" do
      def redisse.channels(env)
        %w(foo bar)
      end
      expect(redirect_params.map(&:first)).to be == %w(foo bar)
    end

    %w(lastEventId polling).each do |reserved|
      it "fails for the reserved channel name '#{reserved}'" do
        def redisse.channels(env)
          [reserved]
        end
        expect { get '/' }.to raise_error(/reserved/i)
      end
    end
  end

  describe "query params" do
    it "passes the lastEventId param" do
      params = redirect_params('/?lastEventId=42')
      expect(params.assoc('lastEventId')).not_to be_nil
    end

    it "passes the polling param" do
      params = redirect_params('/?polling')
      expect(params.assoc('polling')).not_to be_nil
    end

    it "passes lastEventId and polling params" do
      params = redirect_params('/?lastEventId=42&polling')
      expect(params.assoc('lastEventId')).not_to be_nil
      expect(params.assoc('polling')).not_to be_nil
    end

    it "ignores other params" do
      params = redirect_params('/?foo')
      expect(params.assoc('foo')).to be_nil
    end
  end

end
