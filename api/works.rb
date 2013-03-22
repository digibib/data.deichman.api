module API
  class Works < Grape::API
  # /api/works
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
  end
end
