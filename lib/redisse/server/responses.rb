module Redisse
  module Server::Responses
    def plain_response(message = nil, code)
      message ||= "#{code} #{Goliath::HTTP_STATUS_CODES.fetch(code)}\n"
      Rack::Response.new(message, code, 'Content-Type' => 'text/plain')
    end

    def not_acceptable
      plain_response "406 Not Acceptable\n" \
        "This resource can only be represented as text/event-stream.\n",
        406
    end

    def not_found
      plain_response 404
    end

    def service_unavailable
      plain_response 503
    end
  end
end
