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
    def self.open(uri)
      new(uri)
    end

    class << self
      private :new
    end

    def initialize(uri)
      @uri = URI(uri)
      @queue = Queue.new
      @thread = Thread.new { connect }
      @thread.abort_on_exception = true
      event = @queue.pop
      fail ':connected expected' unless event == :connected
    end

    attr_reader :response

    CloseConnection = Class.new StandardError
    def close
      @closed_at = Time.now.to_f
      @thread.raise CloseConnection
    end

    def connected?
      return Net::HTTPOK === response && !@closed
    end

    # #each is blocking while the connection persists
    # call #close in the given block to make #each return
    def each
      return enum_for(:each) unless block_given?
      return unless connected?
      while (event = @queue.pop) != :over
        yield event
      end
    end

    def full_stream
      raise "No stream: response was #@response" unless @scanner
      @scanner.full_stream
    end

  private

    def connect
      Net::HTTP.start(@uri.host, @uri.port) do |http|
        request = Net::HTTP::Get.new @uri
        request['Accept'] = 'text/event-stream'
        response_received = false
        http.request request do |response|
          # Fix a bug? in Net::HTTP where if the connection times out,
          # the block runs again
          return if response_received
          response_received = true
          self.response = response
          read_events if connected?
        end
      end
    rescue CloseConnection
    ensure
      @closed = true
      @queue << :over
    end

    def response=(response)
      @response = response
      @scanner = EventScanner.new { |event| @queue << event }
      @queue << :connected
    end

    def read_events
      @response.read_body do |segment|
        @scanner << segment
        break if @closed
      end
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
    rescue Errno::ESRCH
    end

    def stop
      return unless @pid
      Process.kill("TERM", @pid)
      wait
    ensure
      @pid = nil
    end

    def bin
      __dir__ + '/../example/bin/'
    end
  end

  class Server < Command
    def initialize(server, port)
      @port = port
      check_tcp
      super(server)
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

    def check_tcp
      connection = TCPSocket.new 'localhost', @port
      fail "port #@port already used"
    rescue Errno::ECONNREFUSED
    ensure
      connection.close if connection
    end
  end
end
