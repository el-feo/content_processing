# frozen_string_literal: true

# SimpleCov must be loaded before application code
require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_filter '/vendor/'

  # Require 100% coverage for all files
  minimum_coverage 100
  minimum_coverage_by_file 100

  # Track branch coverage (conditionals, case statements, etc.)
  enable_coverage :branch
  minimum_coverage branch: 100
end

require 'rspec'
require 'json'

# Set default environment variables for testing
ENV['AWS_REGION'] ||= 'us-east-1'
ENV['JWT_SECRET_NAME'] ||= 'pdf-converter/jwt-secret'

# Load all support files
Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/.rspec_status'
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = 'doc' if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed
end
