module Redisse
  class Server::Stats
    def initialize(address, port, config, status, logger)
      status[:stats] = Hash.new(0)
    end

    def run
    end
  end
end
