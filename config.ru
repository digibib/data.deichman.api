require "./api.rb"
logger = Logger.new(File.expand_path("../log/#{ENV['RACK_ENV']}.log", __FILE__))
use Rack::CommonLogger, logger
run API
