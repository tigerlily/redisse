require "bundler/gem_tasks"

begin
  require 'yard'
  YARD::Config.load_plugin 'tomdoc'
  YARD::Rake::YardocTask.new do |t|
    t.name = :doc
  end
rescue LoadError
end
