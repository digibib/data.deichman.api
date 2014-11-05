#encoding: utf-8
module API
  class Reviews < Grape::API
  # /api/reviews
    resource :reviews do
      desc "returns reviews"
        params do
            optional :uri,         desc: "URI of review, accepts array"
            # isbn should be looked up via /api/work
            #optional :isbn,        type: String, desc: "ISBN of reviewed book" #, regexp: /^[0-9Xx-]+$/
            optional :title,       type: String, desc: "Book title"
            optional :author_name, type: String, desc: "Book author"
            optional :author,      type: String, desc: "URI of Book author"
            optional :reviewer,    type: String, desc: "Reviewer's email, uri or name"
            optional :work,        type: String, desc: "URI of Work"
            optional :source,      type: String, desc: "URI of Review's source"
            optional :limit,       type: Integer, desc: "Limit result"
            optional :offset,      type: Integer, desc: "Offset, for pagination" 
            optional :order_by,    type: String, desc: "Order of results" 
            optional :order,       type: String, desc: "Ascending or Descending order" 
            optional :published,   type: Boolean, desc: "Sort by published - true/false" 
            optional :cluster,     type: Boolean, desc: "cluster by works - true/false" 
        end
  
      get "/" do
        reviews = Review.new.find(params)
        if reviews == "Invalid URI"
          logger.error "Invalid URI"
          error!("\"#{params[:uri]}\" is not a valid URI", 400)
        elsif reviews == "Invalid Reviewer"
          logger.error "Invalid Reviewer"
          error!("reviewer \"#{params[:reviewer]}\" not found", 400)
        elsif reviews == "Invalid Source"
          logger.error "Invalid Source"
          error!("source \"#{params[:source]}\" not found", 400)          
        elsif reviews.nil?
          logger.info "no reviews found"
          error!("no reviews found", 200)
        else
          # found reviews, append to works
          works = Review.new.reviews_to_works(reviews)
          logger.info "Works: #{works.count} - Reviews: #{c=0 ; works.each {|w| c += w.reviews.count};c}"
          {:works => works }
        end
      end
  
      desc "creates a review"
        params do
          requires :api_key,   type: String, desc: "Authorization Key"
          requires :isbn,      type: String, desc: "ISBN of reviewed book"
          optional :reviewer,  type: String, desc: "Reviewer's email", email: true
          optional :reviewer_name,  type: String, desc: "Reviewer's name"
          optional :published, type: Boolean, desc: "Published - true/false"
          optional :series,    type: Boolean, desc: "Is review on a series of books? - NOT IMPLEMENTED YET"
          # allow creating draft without :title, :teaser & :text
          unless :published
            requires :title,    type: String, desc: "Title of review"
            requires :teaser,   type: String, desc: "Abstract of review"
            requires :text,     type: String, desc: "Text of review"
            requires :audience, type: String, desc: "Audience comma-separated, barn|ungdom|voksen|children|youth|adult"
          end
        end
      post "/" do
        content_type 'json'
        valid_params = ['api_key','isbn','title','teaser','text','audience', 'reviewer', 'reviewer_name', 'published', 'series']
        if valid_params.any? {|p| params.has_key?(p) }
          params.delete_if {|p| !valid_params.include?(p) }
          work = Work.new.find(:isbn => params[:isbn])
          error!("Sorry, #{params[:isbn]} matches no known book in our base", 400) if work == "Invalid ISBN" || work.nil?
          review = Review.new.create(params)
          error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if review == "Invalid api_key"
          error!("Sorry, unable to create/obtain unique ID of reviewer", 400) if review == "Invalid Reviewer ID"
          error!("Sorry, unable to generate unique ID of review", 400) if review == "Invalid UID"
          result = review.save
          logger.info "POST: params: #{params} - review: #{review}"
          work.first.reviews << review
          {:works => work }
        else
          logger.error "invalid or missing params"   
          error!("Need at least one param of title|teaser|text|audience|reviewer|published", 400)      
        end
      end
      desc "updates a review"
        params do
          requires :api_key,   type: String, desc: "Authorization Key"
          requires :uri,       type: String, desc: "URI of review"
          optional :title,     type: String, desc: "Title of review"
          optional :teaser,    type: String, desc: "Abstract of review"
          optional :text,      type: String, desc: "Text of review"
          optional :audience,  type: String, desc: "Audience comma-separated, barn|ungdom|voksen|children|youth|adult"
          optional :published, type: Boolean, desc: "Published - true/false"
          #optional :reviewer, type: String, desc: "Name of reviewer"
          #optional :source, type: String, desc: "Source of review"
        end    
      put "/" do
        content_type 'json'
        valid_params = ['api_key','uri','title','teaser','text','audience','published']
        # do we have a valid parameter?
        if valid_params.any? {|p| params.has_key?(p) }
          # delete params not listed in valid_params
          logger.info "params before: #{params}"
          params.delete_if {|p| !valid_params.include?(p) }
          logger.info "params after: #{params}"
          # is it in the base? uses params[:uri]
          reviews = Review.new.find(:uri => params[:uri])
          error!("Sorry, \"#{params[:uri]}\" matches no review in our base", 400) if reviews.nil?
          logger.info "works: #{reviews}"
          review = reviews.first.update(params)
          error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if review == "Invalid api_key"
          #throw :error, :status => 400, :message => "Sorry, unable to update review #{params[:uri]} ..." if result =~ /nothing to do/
          logger.info "PUT: params: #{params} - review: #{review}"
          works = Review.new.reviews_to_works(reviews)
          #(works ||=[]) << Work.new.find(:isbn => review.subject).first
          #works.first.reviews << review
          {:works => works }
        else
          logger.error "invalid or missing params"   
          error!("Need at least one param of title|teaser|text|audience|published", 400)      
        end
      end

      desc "updates a review by POST /update - for browser compatibility"
        params do
          requires :api_key,   type: String, desc: "Authorization Key"
          requires :uri,       type: String, desc: "URI of review"
          optional :title,     type: String, desc: "Title of review"
          optional :teaser,    type: String, desc: "Abstract of review"
          optional :text,      type: String, desc: "Text of review"
          optional :audience,  type: String, desc: "Audience comma-separated, barn|ungdom|voksen|children|youth|adult"
          optional :published, type: Boolean, desc: "Published - true/false"
          #optional :reviewer, type: String, desc: "Name of reviewer"
          #optional :source, type: String, desc: "Source of review"
        end    
      post "/update" do
        content_type 'json'
        valid_params = ['api_key','uri','title','teaser','text','audience','published']
        # do we have a valid parameter?
        if valid_params.any? {|p| params.has_key?(p) }
          # delete params not listed in valid_params
          logger.info "params before: #{params}"
          params.delete_if {|p| !valid_params.include?(p) }
          logger.info "params after: #{params}"
          # is it in the base? uses params[:uri]
          reviews = Review.new.find(:uri => params[:uri])
          error!("Sorry, \"#{params[:uri]}\" matches no review in our base", 400) if reviews.nil?
          logger.info "works: #{reviews}"
          review = reviews.first.update(params)
          error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if review == "Invalid api_key"
          #throw :error, :status => 400, :message => "Sorry, unable to update review #{params[:uri]} ..." if result =~ /nothing to do/
          logger.info "PUT: params: #{params} - review: #{review}"
          works = Review.new.reviews_to_works(reviews)
          #(works ||=[]) << Work.new.find(:isbn => review.subject).first
          #works.first.reviews << review
          {:works => works }
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
      delete '/' do
        content_type 'json'
        # is it in the base?
        reviews = Review.new.find(:uri => params[:uri])
        error!("Sorry, \"#{params[:uri]}\" matches no review in our base", 400) if reviews.nil?
        # yes, then delete it!
        result = reviews.first.delete(params)
        error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if reviews == "Invalid api_key"
        error!("Sorry, unable to delete review #{params[:uri]} ...", 400) if reviews.nil? || reviews =~ /nothing to do/
        logger.info "DELETE: params: #{params} - result: #{reviews}"
        {:result => result }
      end

      desc "deletes a review by POST /delete - for browser compatibility"
        params do
          requires :api_key, type: String, desc: "Authorization Key"
          requires :uri,     type: String, desc: "URI of review"
        end    
      post "/delete" do
        content_type 'json'
        # is it in the base?
        reviews = Review.new.find(:uri => params[:uri])
        error!("Sorry, \"#{params[:uri]}\" matches no review in our base", 400) if reviews.nil?
        # yes, then delete it!
        result = reviews.first.delete(params)
        error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if reviews == "Invalid api_key"
        error!("Sorry, unable to delete review #{params[:uri]} ...", 400) if reviews.nil? || reviews =~ /nothing to do/
        logger.info "DELETE: params: #{params} - result: #{reviews}"
        {:result => result }
      end
      
    end
  end
end
