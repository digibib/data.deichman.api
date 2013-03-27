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
          requires :accountName, type: String, desc: "Reviewer's email", regexp: /[[:ascii:]]+@[[:ascii:]]+\.[[:ascii:]]{2,4}/
        end
      post "/" do
        content_type 'json'
        logger.info "params: #{params}"
        reviewer = Reviewer.new.create(params)
        error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if reviewer == "Invalid api_key"
        reviewer.save
        reviewer.password = nil
        {:reviewer => reviewer}
      end

      desc "updates a user"
        params do
          requires :api_key,   type: String, desc: "API key"
          requires :uri,       type: String, desc: "Reviewer URI"
          optional :name,      type: String, desc: "Reviewer's name"
          optional :password,  type: String, desc: "Reviewer's password"
          optional :workplace, type: String, desc: "Reviewer's workplace"
          optional :active,    type: Boolean, desc: "Active? - true/false"
        end
      put "/" do
        content_type 'json'
        logger.info "params: #{params}"
        reviewer = Reviewer.new.find(:api_key =>params[:api_key], :uri => params[:uri])
        error!("Sorry, \"#{params[:api_key]}\" is not a valid api key", 400) if reviewer == "Invalid api_key"
        error!("Sorry, reviewer not found in our base", 404) unless reviewer
        reviewer.update(params)
        reviewer.password = nil
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
        authenticated = false
        user = Reviewer.new.find(:accountName => params["username"])
        if user
          authenticated = true if user.accountName == params["username"] && user.authenticate(params["password"])
        else
          error!("Sorry, username \"#{params[:username]}\" not found", 404)
        end
        status 200
        {:authenticated => authenticated}
      end
    end
  end
end
