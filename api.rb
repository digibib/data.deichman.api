require "grape"

class API < Grape::API
  prefix 'api'

  resource :reviews do
    desc "returns reviews"
    get "/" do
      "Hello world"
    end

    desc "creates a review"
    post "/" do
      "Hello world"
    end

    desc "updates a review"
    put "/" do
      "Hello world"
    end

    desc "deletes a review"
    delete "/" do
      "Hello world"
    end
  end
end