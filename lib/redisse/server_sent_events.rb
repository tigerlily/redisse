module Redisse
  module ServerSentEvents

  module_function

    def server_sent_event(data, options = {})
      str = ''
      str << "retry: #{options[:retry]}\n" if options[:retry]
      str <<    "id: #{options[:id]}\n"    if options[:id]
      str << "event: #{options[:type]}\n"  if options[:type]
      str <<  "data: " + String(data).gsub("\n", "\ndata: ") + "\n"
      str << "\n"
    end

  end
end
