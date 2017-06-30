#encoding: utf-8
require "rubygems"
require "bundler/setup"
require "grape"
require "json"
require "rack/contrib" # needed for RACK::JSONP
require_relative "./config/init.rb"

# trap all exceptions and fail gracefuly with a 500 and a proper message
class ApiErrorHandler < Grape::Middleware::Base

  def call!(env)
    @env = env
    begin
      @app.call(@env)
    rescue Exception => e
      puts "#{e}"
      throw :error, :message => e.message || options[:default_message], :status => 500
    end
  end
end

module API

  # Custom validators
  class Email < Grape::Validations::Base
    def validate_param!(attr_name, params)
      unless params[attr_name] =~ /[[:ascii:]]+@[[:ascii:]]+\.[[:ascii:]]{2,4}/
        throw :error, :status => 400, :message => "#{attr_name}: must be a valid email"
      end
    end
  end

  class Length < Grape::Validations::Base
    def validate_param!(attr_name, params)
      unless params[attr_name].length >= @option
        throw :error, :status => 400, :message => "#{attr_name}: must be at least #{@option} characters long"
      end
    end
  end

  class Root < Grape::API
    use ApiErrorHandler
    use Rack::JSONP

    version 'v1', :using => :header, :vendor => 'deichman.no'
    prefix 'api' # FIXME this does not work, routes are mounted at root path: host:port/route
    format :json
    default_format :json
    rescue_from :all, :backtrace => true

    before do
      puts "#{env['REMOTE_ADDR']} #{env['HTTP_USER_AGENT']} #{env['REQUEST_METHOD']} #{env['REQUEST_PATH']}"
    end

    # Rescue and log validation errors gracefully
    rescue_from Grape::Exceptions::Validation do |e|
      puts "#{e.message}"
      Rack::Response.new(MultiJson.encode(
          'status' => e.status,
          'message' => e.message,
          'param' => e.param),
           e.status)
    end

    # load all external api routes
    Dir[File.dirname(__FILE__) + '/api/*.rb'].each do |file|
      require file
    end

    mount API::Reviews
    mount API::Works
    mount API::Users
    mount API::Sources
  end
end
