# encoding: UTF-8
module API
  class Works < Grape::API
  # /api/works
    resource :works do
      desc "returns works by isbn, work uri, title or author"
        params do
          optional :uri,         type: String, desc: "URI of Work"
          optional :isbn,        type: String, desc: "ISBN of Edition"
          optional :title,       type: String, desc: "Book title"
          optional :author_name, type: String, desc: "Book author"
          optional :author,      type: String, desc: "ID of Book author"
          optional :limit,       type: Integer, desc: "Limit result"
          optional :offset,      type: Integer, desc: "Offset, for pagination" 
          optional :order_by,    type: String, desc: "Order of results" 
          optional :order,       type: String, desc: "Ascending or Descending order" 
          optional :reviews,     type: Boolean, desc: "Include reviews? - true/false"
        end
      get "/" do
        valid_params = ['uri','isbn','title','author','author_name']
        if valid_params.any? {|p| params.has_key?(p) }
          content_type 'json'
          logger.info "params: #{params}"
          works = Work.new.find(params)
          error!("Sorry, no work found to match criteria", 400) unless works
          {:works => works}
        else
          logger.error "invalid or missing params"
          error!("Need at least one param of uri|isbn|title|author|author_name", 400)      
        end
      end
    end
  end
end
