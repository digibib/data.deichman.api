#encoding: utf-8
$stdout.sync = true
require "rubygems"
require "bundler/setup"
require "grape"
require "json"
require_relative "./config/init.rb"

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
  rescue_from :all, :backtrace => true
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
    Rack::Response.new(MultiJson.encode(
        'status' => e.status,
        'message' => e.message,
        'param' => e.param),
         e.status) 
  end

  resource :reviews do
    desc "returns reviews"
      params do
          optional :uri,       desc: "URI of review, accepts array"
          optional :isbn,      type: String, desc: "ISBN of reviewed book" #, regexp: /^[0-9Xx-]+$/
          optional :title,     type: String, desc: "Book title"
          optional :author,    type: String, desc: "Book author"
          optional :author_id, type: String, desc: "ID of Book author"
          optional :reviewer,  type: String, desc: "Review author"
          optional :work,      type: String, desc: "Work ID"
          optional :workplace, type: String, desc: "Reviewer's workplace"
          optional :limit,     type: Integer, desc: "Limit result"
          optional :offset,    type: Integer, desc: "Offset, for pagination" 
          optional :order_by,  type: String, desc: "Order of results" 
          optional :order,     type: String, desc: "Ascending or Descending order" 
          optional :published, coerce: Virtus::Attribute::Boolean, desc: "Sort by published - true/false" 
      end

    get "/" do
      #header['Content-Type'] = 'application/json; charset=utf-8'
      content_type 'json'
      works = Review.new.find(params)
      if works == "Invalid URI"
        logger.error "Invalid URI"
        error!("\"#{params[:uri]}\" is not a valid URI", 400)
      elsif works == "Invalid Reviewer"
        logger.error "Invalid Reviewer"
        error!("reviewer \"#{params[:reviewer]}\" not found", 400)
      elsif works == "Invalid Workplace"
        logger.error "Invalid Workplace"
        error!("workplace \"#{params[:workplace]}\" not found", 400)          
      elsif works.nil? || works.empty?
        logger.info "no reviews found"
        error!("no reviews found", 200)
      else
        logger.info "Works: #{works.count} - Reviews: #{c=0 ; works.each {|w| c += w.reviews.count};c}"
        {:works => works }
      end
    end

    desc "creates a review"
      params do
        requires :api_key,   type: String, desc: "Authorization Key"
        requires :isbn,      type: String, desc: "ISBN of reviewed book"
        optional :audience,  type: String, desc: "Audience comma-separated, barn|ungdom|voksen|children|youth|adult"
        optional :reviewer,  type: String, desc: "Name of reviewer"
        optional :published, type: Boolean, desc: "Published - true/false"
        # allow creating draft without :title, :teaser & :text
        unless :published
          requires :title,   type: String, desc: "Title of review"
          requires :teaser,  type: String, desc: "Abstract of review"
          requires :text,    type: String, desc: "Text of review"
        end
      end
    post "/" do
      content_type 'json'
      review = Review.new.create(params)
      error!("Sorry, #{params[:isbn]} matches no known book in our base", 400) if review == "Invalid ISBN"
      error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if review == "Invalid api_key"
      error!("Sorry, unable to create/obtain unique ID of reviewer", 400) if review == "Invalid Reviewer ID"
      error!("Sorry, unable to generate unique ID of review", 400) if review == "Invalid UID"
      result = review.save
      logger.info "POST: params: #{params} - review: #{review}"
      {:review => review }

    end
    desc "updates a review"
      params do
        requires :api_key,   type: String, desc: "Authorization Key"
        requires :uri,       type: String, desc: "URI of review"
        optional :title,     type: String, desc: "Title of review"
        optional :teaser,    type: String, desc: "Abstract of review"
        optional :text,      type: String, desc: "Text of review"
        optional :audience,  type: String, desc: "Audience comma-separated, barn|ungdom|voksen|children|youth|adult"
        optional :published, coerce: Virtus::Attribute::Boolean, desc: "Published - true/false"
        #optional :reviewer, type: String, desc: "Name of reviewer"
        #optional :source, type: String, desc: "Source of review"
      end    
    put "/" do
      content_type 'json'
      #header['Content-Type'] = 'application/json; charset=utf-8'
      valid_params = ['api_key','uri','title','teaser','text','audience','published']
      # do we have a valid parameter?
      if valid_params.any? {|p| params.has_key?(p) }
        # delete params not listed in valid_params
        logger.info "params before: #{params}"
        params.delete_if {|p| !valid_params.include?(p) }
        logger.info "params after: #{params}"
        # is it in the base? uses params[:uri]
        works = Review.new.find(:uri => params[:uri])
        error!("Sorry, \"#{params[:uri]}\" matches no review in our base", 400) if works.nil?
        logger.info "works: #{works}"
        review = works.first.reviews.first.update(params)
        error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if works == "Invalid api_key"
        #throw :error, :status => 400, :message => "Sorry, unable to update review #{params[:uri]} ..." if result =~ /nothing to do/
        logger.info "PUT: params: #{params} - review: #{works}"
        {:review => review }
      else
        logger.error "invalid or missing params"   
        error!("Need at least one param of title|teaser|text|audience|published", 400)      
      end
    end

    desc "deletes a review"
      params do
        requires :api_key, type: String, desc: "Authorization Key"
        requires :uri,     type: String, desc: "URI of review"
      end    
    delete "/" do
      #header['Content-Type'] = 'application/json; charset=utf-8'
      content_type 'json'
      # is it in the base?
      works = Review.new.find(:uri => params[:uri])
      error!("Sorry, \"#{params[:uri]}\" matches no review in our base", 400) if works.nil?
      # yes, then delete it!
      result = works.first.reviews.first.delete(params)
      error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if works == "Invalid api_key"
      error!("Sorry, unable to delete review #{params[:uri]} ...", 400) if works.nil? || works =~ /nothing to do/
      logger.info "DELETE: params: #{params} - result: #{works}"
      {:result => result, :review => works.first.reviews.first }
    end
  end
  
  resource :works do
    desc "returns works, only by isbn for now"
      params do
        requires :isbn,      type: String, desc: "ISBN"
        optional :title,     type: String, desc: "Book title"
        optional :author,    type: String, desc: "Book author"
        optional :author_id, type: String, desc: "ID of Book author"
        optional :limit,     type: Integer, desc: "Limit result"
        optional :offset,    type: Integer, desc: "Offset, for pagination" 
        optional :order_by,  type: String, desc: "Order of results" 
        optional :order,     type: String, desc: "Ascending or Descending order" 
      end
    get "/" do
      content_type 'json'
      logger.info "params: #{params}"
      work = Work.new.find(params)
      error!("Sorry, \"#{params[:uri]}\" matches no review in our base", 400) unless work
      {:work => work}
    end
  end
  
  resource :users do

    desc "returns all users or specific user"
    get "/" do
      content_type 'json'
      unless params[:uri] || params[:name]
        users = Reviewer.new.all
        {:users => users }
      else
        logger.info "params: #{params}"
        user = Reviewer.new.find(params)
        error!("Sorry, user not found", 401) unless user
        user.password = nil
        {:user => user }
      end
    end

    desc "creates a user"
      params do
        requires :api_key,   type: String, desc: "API key"
        requires :name,      type: String, desc: "Reviewer's name"
      end    
    post "/" do
      content_type 'json'
      logger.info "params: #{params}"
      reviewer = Reviewer.new.create(params)
      error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if reviewer == "Invalid api_key"
      reviewer.save
      {:reviewer => reviewer}
    end
    
    desc "updates a user"
      params do
        requires :api_key,   type: String, desc: "API key"
        optional :name,      type: String, desc: "Reviewer's name"
        optional :password,  type: String, desc: "Reviewer's password"
        optional :email,     type: String, desc: "Reviewer's email"
        optional :workplace, type: String, desc: "Reviewer's workplace"
        optional :active,    type: Boolean, desc: "Active? - true/false"
      end
    put "/" do
      content_type 'json'
      logger.info "params: #{params}"
      reviewer = Reviewer.new.find(params)
      error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if reviewer == "Invalid api_key"
      error!("Sorry, \"#{params[:uri]}\" matches no review in our base", 400) unless reviewer
      reviewer.update(params)
      {:reviewer => reviewer}    
    end
    
    desc "deletes a user"
      params do
        requires :api_key,   type: String, desc: "API key"
        requires :uri,       type: String, desc: "Reviewer URI"
      end
    delete "/" do
      content_type 'json'
      logger.info "params: #{params}"
      reviewer = Reviewer.new.find(params)
      error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if reviewer == "Invalid api_key"
      error!("Sorry, \"#{params[:uri]}\" matches no review in our base", 400) unless reviewer
      result = reviewer.delete(params)
      {:result => result}   
    end
    
    desc "authenticates a user"
      params do
        requires :username,   type: String, desc: "Reviewer accountName"
        requires :password,   type: String, desc: "account password"
      end
    post "/authenticate" do
      authenticated = false

      user = Reviewer.new.find(:name => params["username"])
      if user
        authenticated = true if user.accountName == params["username"] && user.authenticate(params["password"])
      else
        error!("Sorry, username \"#{params[:username]}\" not found", 401)
      end
      status 200 if authenticated
      {:authenticated => authenticated}
    end    
  end 
  
  resource :sources do 

    desc "returns all users or specific user"
    get "/" do
      error!('Unauthorized', 401) unless env['HTTP_SECRET_SESSION_KEY'] == SECRET_SESSION_KEY
      content_type 'json'
      unless params[:uri] || params[:name]
        sources = {:sources => Source.new.all }
      else
        logger.info "params: #{params}"
        source = Source.new.find(params)
        error!("Sorry, source not found", 401) unless source
        {:source => source }
      end
    end
  end
  
end
