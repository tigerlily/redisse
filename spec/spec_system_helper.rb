require 'spec_helper'
require 'socket'
require 'net/http'
require 'strscan'

shared_context "system" do
  # Classes are not accessible from before, after hooks
  # methods are
  def run_command(*args)
    Command.new(*args).run
  end

  def run_server(*args)
    Server.new(*args)
  end

  Event = Struct.new :data, :type, :id

  class EventReader
    def initialize(uri)
      @uri = URI(uri)
      @queue = Queue.new
      @thread = Thread.new do
        connect
        @queue << :over
      end
    end

    def stop
      @stop = true
      @thread.exit
    end

    def connected?
      return Net::HTTPOK === response
    end

    def response
      ensure_response
      @response
    end

    def ensure_response
      return if defined? @response
      @response = @queue.pop
    end

    def connect
      Net::HTTP.start(@uri.host, @uri.port) do |http|
        request = Net::HTTP::Get.new @uri
        request['Accept'] = 'text/event-stream'
        response_pushed = false
        http.request request do |response|
          # Fix a bug? in Net::HTTP where if the connection times out,
          # the block runs again
          return if response_pushed
          response_pushed = true
          @queue << response
          return unless Net::HTTPOK === response
          @reader = EventScanner.new { |event| @queue << event }
          response.read_body do |segment|
            @reader << segment
            break if @stop
          end
        end
      end
    end

    # #each is blocking while the connection persists
    # call #stop in the given block to make #each return
    def each
      return enum_for(:each) unless block_given?
      return unless connected?
      # either stop asked or thread over
      while !@stop && (event = @queue.pop) != :over
        yield event
      end
      # @stop may not be true if the connection closed by itself
    end

    def full_stream
      @reader.full_stream
    end
  end

  class EventScanner
    def initialize(&block)
      @body = StringScanner.new ""
      @event = Event.new ""
      @block = block
    end

    def <<(segment)
      @body << segment
      return unless lines = @body.scan_until(/\n\n/)
      lines.split("\n").each do |line|
        field, value = line.split(/: ?/, 2)
        next if field.empty?
        case field
        when "id"
          @event.id = value
        when "event"
          @event.type = value
        when "data"
          @event.data << value if value
          @event.data << "\n"
        end
      end
      @event.data.chomp!
      @block.call @event
      @event = Event.new ""
    end

    def full_stream
      @body.string.dup
    end
  end

  class Command
    def initialize(command)
      @command = command
    end

    def run
      start.wait
    end

    def start
      @pid = Process.spawn("#{bin}#@command", %i(in out err) => :close)
      self
    end

    def wait
      Process.wait(@pid)
    end

    def stop
      Process.kill("TERM", @pid)
    end

    def bin
      __dir__ + '/../example/bin/'
    end
  end

  class Server < Command
    def initialize(server, port)
      super(server)
      @port = port
      start
    end

    def wait_tcp
      connection = TCPSocket.new 'localhost', @port
      self
    rescue
      retry
    ensure
      connection.close
    end
  end
end
