require 'rubygems'
 
ENV["RACK_ENV"] ||= 'test'
 
require 'rack/test'
require File.join(File.dirname(__FILE__), '..', 'api.rb')

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start
end

RSpec.configure do |config|
  config.mock_with :rspec
  config.expect_with :rspec
end
