module Redisse
  module ServerSentEvents

  module_function

    def server_sent_event(data, type: nil, id: nil, **options)
      data = String(data)
      str = ''
      str << "retry: #{options[:retry]}\n" if options[:retry]
      str << "id: #{id}\n" if id
      str << "event: #{type}\n" if type
      str << "data: " + data.gsub("\n", "\ndata: ") + "\n"
      str << "\n"
    end

  end
end
