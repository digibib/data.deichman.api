# encoding: UTF-8
module API
  class Users < Grape::API
  # /api/users
    resource :users do

      desc "returns all users or specific user"
      get "/" do
        content_type 'json'
        unless params[:uri] || params[:name] || params[:accountName]
          reviewers = Reviewer.new.all
          {:reviewers => reviewers }
        else
          logger.info "params: #{params}"
          reviewer = Reviewer.new.find(params)
          error!("Sorry, user not found", 404) unless reviewer
          reviewer.password = nil
          {:reviewer => reviewer }
        end
      end

      desc "creates a user"
        params do
          requires :api_key,     type: String, desc: "API key"
          requires :accountName, type: String, desc: "Reviewer's email", email: true
        end
      post "/" do
        content_type 'json'
        logger.info "params: #{params}"
        reviewer = Reviewer.new.create(params)
        error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if reviewer == "Invalid api_key"
        error!("Sorry, \"unable to create reviewer", 400) unless reviewer
        account  = Account.new.create(params)
        error!("Sorry, \"unable to create account", 400) unless account
        account.save
        reviewer.userAccount = account.uri
        reviewer.save
        reviewer.password = nil
        {:reviewer => reviewer}
      end

      desc "updates a user"
        params do
          requires :api_key,   type: String, desc: "API key"
          requires :uri,       type: String, desc: "Reviewer URI"
          optional :name,      type: String, desc: "Reviewer's name"
          optional :password,  type: String, desc: "Account password"
          #optional :workplace, type: String, desc: "Reviewer's workplace"
          optional :active,    type: Boolean, desc: "Active? - true/false"
        end
      put "/" do
        content_type 'json'
        logger.info "params: #{params}"
        reviewer = Reviewer.new.find(:api_key =>params[:api_key], :uri => params[:uri])
        error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if reviewer == "Invalid api_key"
        error!("Sorry, reviewer not found in our base", 404) unless reviewer
        # update Reviewer
        if params[:name] 
          reviewer.update(:name => params[:name])
        end
        if params[:password] || params[:active] || params[:accountName]
          account = Account.new.find(:api_key => params[:api_key], :uri => reviewer.userAccount)
          account.update(params)
          account.password     = nil
          reviewer.userAccount = account
        end
        {:reviewer => reviewer}
      end

      # Deleting a user should mean deleting UserAccount and setting Reviewer to anonymous on reviews
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
        error!("Sorry, \"#{params[:uri]}\" matches no reviewer in our base", 404) unless reviewer
        result = reviewer.delete(params)
        {:result => result}
      end

      desc "authenticates a user"
        params do
          requires :username,   type: String, desc: "Reviewer accountName"
          requires :password,   type: String, desc: "account password"
        end
      post "/authenticate" do
        content_type 'json'
        authenticated = false
        user = Account.new.find(:accountName => params[:username])
        if user
          authenticated = true if user.accountName == params[:username] && user.authenticate(params[:password])
        else
          error!("Sorry, username \"#{params[:username]}\" not found", 404)
        end
        status 200
        {:authenticated => authenticated}
      end
    
      # MyLists specific to user
      resource :mylists do
        desc "returns all users or specific user"
          params do
            requires :api_key,  type: String, desc: "API key"
            requires :reviewer, type: String, desc: "Reviewer URI"
            optional :list,     type: String, desc: "MyList URI"
          end
        get "/" do
          content_type 'json'
          mylists = []
          reviewer = Reviewer.new.find(:uri => params[:reviewer])
          error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if reviewer == "Invalid api_key"
          account = Account.new.find(:uri => reviewer.userAccount)
          unless params[:list]
            account.myLists.each {|list| mylists << MyList.new.find(:uri => list) }
          else
            mylists << MyList.new.find(:uri=> params[:list])
          end
          {:mylists => mylists }
        end
        
        desc "creates a list"
          params do
            requires :api_key,  type: String, desc: "API key"
            requires :reviewer, type: String, desc: "Reviewer URI"
            requires :label,    type: String, desc: "MyList label"
            requires :items,    type: Array, desc: "MyList Array"
          end
        post "/" do
          content_type 'json'
          logger.info "params: #{params}"
          reviewer = Reviewer.new.find(:uri => params[:reviewer])
          error!("Sorry, reviewer not found in our base", 404) unless reviewer
          error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if reviewer == "Invalid api_key"
          mylist = MyList.new.create(params)
          error!("Sorry, \"unable to create mylist", 400) unless mylist
          mylist.save
          account = Account.new.find(:uri => reviewer.userAccount)
          account.myLists << mylist.uri
          account.update(params)
          {:mylists => [mylist]}
        end
        
        desc "updates a list"
          params do
            requires :api_key, type: String, desc: "API key"
            requires :uri,     type: String, desc: "MyList URI"
            optional :label,   type: String, desc: "MyList label"
            optional :items,   type: Array, desc: "MyList Array"
          end
        put "/" do
          content_type 'json'
          logger.info "params: #{params}"
          mylist = MyList.new.find(:api_key =>params[:api_key], :uri => params[:uri])
          error!("Sorry, list not found in our base", 404) unless mylist
          error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if mylist == "Invalid api_key"
          mylist.update(params)
          {:mylist => [mylist]}
        end

        desc "deletes a list"
          params do
            requires :api_key, type: String, desc: "API key"
            requires :uri,     type: String, desc: "MyList URI"
          end
        delete "/" do
          content_type 'json'
          logger.info "params: #{params}"
          mylist = MyList.new.find(:api_key => params[:api_key], :uri => params[:uri])
          error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if mylist == "Invalid api_key"
          error!("Sorry, \"#{params[:uri]}\" matches no reviewer in our base", 404) unless mylist
          result = mylist.delete(params)
          {:result => result}
        end
                    
      end # end MyLists
    end
  end
end
