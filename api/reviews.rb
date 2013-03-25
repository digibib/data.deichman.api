#encoding: utf-8
module API
  class Reviews < Grape::API
  # /api/reviews
    resource :reviews do
      desc "returns reviews"
        params do
            optional :uri,         desc: "URI of review, accepts array"
            optional :isbn,        type: String, desc: "ISBN of reviewed book" #, regexp: /^[0-9Xx-]+$/
            optional :title,       type: String, desc: "Book title"
            optional :author_name, type: String, desc: "Book author"
            optional :author,      type: String, desc: "URI of Book author"
            optional :reviewer,    type: String, desc: "URI of Review author"
            optional :work,        type: String, desc: "URI of Work"
            optional :workplace,   type: String, desc: "URI of Reviewer's workplace"
            optional :limit,       type: Integer, desc: "Limit result"
            optional :offset,      type: Integer, desc: "Offset, for pagination" 
            optional :order_by,    type: String, desc: "Order of results" 
            optional :order,       type: String, desc: "Ascending or Descending order" 
            optional :published,   type: Boolean, desc: "Sort by published - true/false" 
            optional :cluster,     type: Boolean, desc: "cluster by works - true/false" 
        end
  
      get "/" do
        #header['Content-Type'] = 'application/json; charset=utf-8'
        content_type 'json'
        reviews = Review.new.find(params)
        if reviews == "Invalid URI"
          logger.error "Invalid URI"
          error!("\"#{params[:uri]}\" is not a valid URI", 400)
        elsif reviews == "Invalid Reviewer"
          logger.error "Invalid Reviewer"
          error!("reviewer \"#{params[:reviewer]}\" not found", 400)
        elsif reviews == "Invalid Workplace"
          logger.error "Invalid Workplace"
          error!("workplace \"#{params[:workplace]}\" not found", 400)          
        elsif reviews.nil?
          logger.info "no reviews found"
          error!("no reviews found", 200)
        else
          # found reviews, append to works
          works = Review.new.populate_works_from_reviews(reviews)
          #reviews.each do |review|
          #  (@works ||=[]) << Work.new.find(:isbn => review.subject).first
          #end
          #logger.info "Works: #{@works.count} - Reviews: #{c=0 ; @works.each {|w| c += w.reviews.count};c}"
          {:works => works }
        end
      end
  
      desc "creates a review"
        params do
          requires :api_key,   type: String, desc: "Authorization Key"
          requires :isbn,      type: String, desc: "ISBN of reviewed book"
          optional :reviewer,  type: String, desc: "Name of reviewer"
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
        valid_params = ['api_key','isbn','title','teaser','text','audience', 'reviewer', 'published', 'series']
        if valid_params.any? {|p| params.has_key?(p) }
          params.delete_if {|p| !valid_params.include?(p) }
          review = Review.new.create(params)
          error!("Sorry, #{params[:isbn]} matches no known book in our base", 400) if review == "Invalid ISBN"
          error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if review == "Invalid api_key"
          error!("Sorry, unable to create/obtain unique ID of reviewer", 400) if review == "Invalid Reviewer ID"
          error!("Sorry, unable to generate unique ID of review", 400) if review == "Invalid UID"
          result = review.save
          logger.info "POST: params: #{params} - review: #{review}"
          (works ||=[]) << Work.new.find(:isbn => params[:isbn]).first
          works.first.reviews << review
          {:works => works }
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
        #header['Content-Type'] = 'application/json; charset=utf-8'
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
          (works ||=[]) << Work.new.find(:isbn => review.subject).first
          works.first.reviews << review
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
  end
end
