# encoding: UTF-8
module API
  class Sources < Grape::API
  # /api/sources
    resource :sources do 
  
      desc "returns all users or specific user"
      get "/" do
        # Sources is a protected module
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
      
      desc "creates a source"
        params do
          requires :name,     type: String, length: 5, desc: "Name of source"
          optional :homepage, type: String, desc: "Source homepage"
        end
      post "/" do
        # Sources is a protected module
        error!('Unauthorized', 401) unless env['HTTP_SECRET_SESSION_KEY'] == SECRET_SESSION_KEY
        content_type 'json'
        logger.info "params: #{params}"
        
        source = Source.new.create(params)
        error!("Sorry, source name must be unique", 400) if source == "source must be unique"
        source.save
        source.api_key = nil
        {:source => source}
      end
      
      desc "edit/update source"
        params do
          requires :uri,      type: String, desc: "URI of source"
          optional :name,     type: String, length: 5, desc: "Name of source"
          optional :homepage, type: String, desc: "Source homepage"
        end
      put "/" do
        # Sources is a protected module
        error!('Unauthorized', 401) unless env['HTTP_SECRET_SESSION_KEY'] == SECRET_SESSION_KEY
        content_type 'json'
        valid_params = ['uri','name','homepage']
        # do we have a valid parameter?
        if valid_params.any? {|p| params.has_key?(p) }
          source = Source.new.find(:uri => params[:uri])
          source.update(params)
          logger.info "updated source: #{source}"
          { :source => source}
        else
          logger.error "invalid or missing params"   
          error!("Need at least one param of uri|name|homepage", 400)      
        end
      end
      
      desc "delete a source"
        params do
          requires :uri,      type: String, desc: "URI of source"
        end
      delete "/" do
        # Sources is a protected module
        error!('Unauthorized', 401) unless env['HTTP_SECRET_SESSION_KEY'] == SECRET_SESSION_KEY
        content_type 'json'
        source = Source.new.find(:uri => params[:uri])
        result = source.delete
        logger.info "DELETE: params: #{params} - deleted source: #{source}"
        { :result => result }
      end 
    end
  end
end
