require "bundler/gem_tasks"

begin
  require 'yard'
  YARD::Config.load_plugin 'tomdoc'
  YARD::Rake::YardocTask.new do |t|
    t.name = :doc
  end

  task :gh_pages => :doc do
    sh 'git checkout gh-pages'
    sh 'rsync -a doc/* .'
    sh 'git add .'
    version = "v#{Bundler::GemHelper.gemspec.version}"
    sh "git commit -m 'Documentation for #{version}'"
    sh 'git checkout -'
  end

rescue LoadError
end
