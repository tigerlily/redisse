require 'uri'

module Redisse

  # Public: Rack app that redirects to the Redisse server via X-Accel-Redirect.
  class RedirectEndpoint

    def initialize(redisse)
      @redisse = redisse
      self.base_url = redisse.nginx_internal_url
    end

    def call(env)
      response = Rack::Response.new
      response['X-Accel-Redirect'] = redirect_url(env)
      response
    end

  private

    def redirect_url(env)
      channels = @redisse.channels(env)
      fail 'Wrong channel "polling"' if channels.include? 'polling'
      fail 'Reserved channel "lastEventId"' if channels.include? 'lastEventId'
      @base_url + '?' + URI.encode_www_form(redirect_options(env) + channels)
    end

    def redirect_options(env)
      params = URI.decode_www_form(env['QUERY_STRING'])
      [].tap do |options|
        options << 'polling'.freeze if params.assoc('polling'.freeze)
        last_event_id_param = params.assoc('lastEventId')
        options << last_event_id_param if last_event_id_param
      end
    end

    def base_url=(url)
      url = String(url)
      url += "/" unless url.end_with? '/'
      @base_url = url
    end

  end

end
