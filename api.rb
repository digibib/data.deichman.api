#encoding: utf-8
$stdout.sync = true

require "bundler/setup"
require "grape"
require "./lib/review.rb"

# trap all exceptions and fail gracefuly with a 500 and a proper message
class ApiErrorHandler < Grape::Middleware::Base
  def call!(env)
    @env = env
    begin
      @app.call(@env)
    rescue Exception => e
      throw :error, :message => e.message || options[:default_message], :status => 500
    end
  end  
end


class API < Grape::API
  helpers do
    def logger
      logger = Logger.new(File.expand_path("../logs/#{ENV['RACK_ENV']}.log", __FILE__))
    end
    
  end
  version 'v1', :using => :header, :vendor => 'deichman.no'
  prefix 'api'
  format :json
  default_format :json
  #use ApiErrorHandler
  
  before do
    # Of course this makes the request.body unavailable afterwards.
    # You can just use a helper method to store it away for later if needed. 
    logger.info "#{env['REMOTE_ADDR']} #{env['HTTP_USER_AGENT']} #{env['REQUEST_METHOD']} #{env['REQUEST_PATH']} -- Request: #{request.body.read}"
  end
  
  # Rescue and log validation errors gracefully
  rescue_from Grape::Exceptions::ValidationError do |e|
    logger = Logger.new(File.expand_path("../logs/#{ENV['RACK_ENV']}.log", __FILE__))
    logger.error "#{e.message}"
    Rack::Response.new({
        'status' => e.status,
        'message' => e.message,
        #'param' => e.param
    }.to_json, e.status) 
  end

  resource :reviews do
    desc "returns reviews"
      params do
          optional :uri,      type: String, desc: "URI of review"
          optional :isbn,     type: String, desc: "ISBN of reviewed book" #, regexp: /^[0-9Xx-]+$/
          optional :title,    type: String, desc: "Book title"
          optional :author,   type: String, desc: "Book author"
          optional :reviewer, type: String, desc: "Review author"

      end

    get "/" do
      content_type 'json'
      if [:uri,:isbn,:author,:title,:reviewer,:work].any? {|p| params.has_key?(p) }
        works = Review.new.find_reviews(params)
        if works == "Invalid URI"
          logger.error "Invalid URI"
          error!("\"#{params[:uri]}\" is not a valid URI", 400)
        elsif works.empty? 
          logger.info "no reviews found"
          error!("no reviews found", 200)
        else
          logger.info "Works: #{works.count} - Reviews: #{c=0 ; works.each {|w| c += w.reviews.count};c}"
          header['Content-Type'] = 'application/json; charset=utf-8'
          {:works => works }
        end
      else
        logger.error "invalid or missing params"   
        error!("Need one param of isbn|uri|author|title|reviewer", 400)
      end
    end

    desc "creates a review"
      params do
        requires :api_key,  type: String, desc: "Authorization Key"
        requires :title,    type: String, desc: "Title of review"
        requires :teaser,   type: String, desc: "Abstract of review"
        requires :text,     type: String, desc: "Text of review"
        requires :isbn,     type: String, desc: "ISBN of reviewed book" #, regexp: /^[0-9Xx-]+$/
        optional :audience, type: String, desc: "Audience comma-separated, barn|ungdom|voksen|children|youth|adult" #, regexp: /([Vv]oksen|[Aa]dult|[Bb]arn|[Uu]ngdom|[Jj]uvenile)/
        optional :reviewer, type: String, desc: "Name of reviewer"
        #optional :source, type: String, desc: "Source of review"
      end
    post "/" do
      content_type 'json'
      work = Review.new.create(params)
      error!("Sorry, #{params[:isbn]} matches no known book in our base", 400) if work == "Invalid ISBN"
      error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if work == "Invalid api_key"
      error!("Sorry, unable to generate unique ID of review", 400) if work == "Invalid UID"
      error!("Sorry, unable to obtain unique ID of reviewer", 400) if work == "Invalid Reviewer ID"
      
      logger.info "POST: params: #{params} - review: #{work.reviews}"
      header['Content-Type'] = 'application/json; charset=utf-8' 
      {:work => work }
    end

    desc "updates a review"
      params do
        requires :api_key,  type: String, desc: "Authorization Key"
        requires :uri,      type: String, desc: "URI of review"
        optional :title,    type: String, desc: "Title of review"
        optional :teaser,   type: String, desc: "Abstract of review"
        optional :text,     type: String, desc: "Text of review"
        optional :audience, type: String, desc: "Audience comma-separated, barn|ungdom|voksen|children|youth|adult" #, regexp: /([Vv]oksen|[Aa]dult|[Bb]arn|[Uu]ngdom|[Jj]uvenile)/
        #optional :reviewer, type: String, desc: "Name of reviewer"
        #optional :source, type: String, desc: "Source of review"
      end    
    put "/" do
      content_type 'json'
      valid_params = ['api_key','uri','title','teaser','text','audience']
      # do we have a valid parameter?
      if valid_params.any? {|p| params.has_key?(p) }
        # delete params not listed in valid_params
        logger.info "params before: #{params}"
        params.delete_if {|p| !valid_params.include?(p) }
        logger.info "params after: #{params}"
        # is it in the base? uses params[:uri]
        before = Review.new.find_reviews(params)
        error!("Sorry, \"#{params[:uri]}\" matches no review in our base", 400) if before.empty?
        # yes, then update
        after = Review.new.update(params)
        #after = after.first.reviews.first.update(params)
        error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if after == "Invalid api_key"
        #throw :error, :status => 400, :message => "Sorry, unable to update review #{params[:uri]} ..." if result =~ /nothing to do/
        
        header['Content-Type'] = 'application/json; charset=utf-8' 
        logger.info "PUT: params: #{params} - review: #{after.reviews}"
        {:after => after, :before => before.first }
      else
        logger.error "invalid or missing params"   
        error!("Need at least one param of title|teaser|text|audience", 400)      
      end
    end

    desc "deletes a review"
      params do
        requires :api_key, type: String, desc: "Authorization Key"
        requires :uri,     type: String, desc: "URI of review"
      end    
    delete "/" do
      content_type 'json'
      # is it in the base?
      review = Review.new.find_reviews(params)
      error!("Sorry, \"#{params[:uri]}\" matches no review in our base", 400) if review.empty?
      # yes, then delete it!
      result = Review.new.delete(params)
      error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if result == "Invalid api_key"
      error!("Sorry, unable to delete review #{params[:uri]} ...", 400) if result =~ /nothing to do/
      logger.info "DELETE: params: #{params} - result: #{result}"
      header['Content-Type'] = 'application/json; charset=utf-8' 
      {:result => result, :review => review }
    end
  end
end
