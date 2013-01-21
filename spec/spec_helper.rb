require 'rubygems'
require 'bundler'
require 'grape'
require 'rspec/mocks'
Bundler.setup :default, :test

require 'rack/test'
require File.join(File.dirname(__FILE__), '..', 'api.rb')

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start
end

RSpec.configure do |config|
  config.include Rack::Test::Methods
end
