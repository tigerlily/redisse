RSpec.configure do |config|
  config.mock_with :rspec
  config.expect_with :rspec
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
