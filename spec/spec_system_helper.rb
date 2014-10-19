require 'spec_helper'
require 'socket'
require 'net/http'
require 'strscan'
require 'English'
require 'json'
require 'matrix'
require 'dotenv'
Dotenv.load 'example/.env'

REDIS_PORT    = ENV['REDIS_PORT']
REDISSE_PORT  = ENV['REDISSE_PORT']
REDISSE_REDIS = ENV['REDISSE_REDIS']

shared_context "system" do
  # Classes are not accessible from before, after hooks
  # methods are
  def run_server(*args)
    Server.new(*args)
  end

  Event = Struct.new :data, :type, :id

  class EventReader
    def self.open(*args, &block)
      reader = new(*args)
      if block_given?
        yield_and_close(reader, &block)
      else
        reader
      end
    end

    class << self
      private :new

    private
      def yield_and_close(reader)
        yield reader
      ensure
        reader.close
      end
    end

    def initialize(uri, last_event_id = nil)
      @uri = URI(uri)
      @last_event_id = last_event_id
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
        response_received = false
        headers = { 'Accept' => 'text/event-stream' }
        headers['Last-Event-Id'] = @last_event_id.to_s if @last_event_id
        http.request_get @uri, headers do |response|
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
      while lines = @body.scan_until(/\n\n/)
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
    end

    def full_stream
      @body.string.dup
    end
  end

  class Server
    ROOT = File.expand_path __dir__ + '/..'

    def initialize(command, port, pidfile: nil)
      @command = command
      @port = port
      @pidfile = pidfile
      check_tcp
      start
    end

    def start
      @pid = Process.spawn("#{ROOT}/#@command", %i(in out err) => :close)
      @pid = pid_from_pidfile if @pidfile
      fail "#@command could not be started" unless @pid
    end

    def pid_from_pidfile
      wait
      @pid = nil
      return unless $CHILD_STATUS.success?
      wait_pidfile
      File.read(@pidfile).to_i
    end

    def wait_pidfile
      Timeout.timeout(5) do
        sleep(0.1) until File.exist?(@pidfile)
      end
    rescue Timeout::Error
      fail "Server did not write pid to #@pidfile"
    end

    def wait_pidfile_removal
      Timeout.timeout(5) do
        sleep(0.1) if File.exist?(@pidfile)
      end
    rescue Timeout::Error
      fail "Server did not remove pidfile #@pidfile"
    end

    def wait
      return unless @pid
      Process.wait(@pid)
    rescue Errno::ESRCH
    end

    def stop
      return unless @pid
      Process.kill("TERM", @pid)
      wait_stopped
    ensure
      @pid = nil
    end

    def wait_stopped
      if @pidfile
        wait_pidfile_removal
      else
        wait
      end
    end

    def wait_tcp
      Timeout.timeout(5) do
        _wait_tcp
      end
    rescue Timeout::Error
      fail "Could not connect to server at localhost:#@port"
    end

    def _wait_tcp
      connection = TCPSocket.new 'localhost', @port
      self
    rescue
      retry
    ensure
      connection.close if connection
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
