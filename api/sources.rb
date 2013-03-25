# encoding: UTF-8
module API
  class Sources < Grape::API
  # /api/sources
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
end
