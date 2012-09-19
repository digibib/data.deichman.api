require "minitest/autorun"
require "rack/test"
require "./api.rb"

describe API do
  include Rack::Test::Methods

  def app
    API
  end

  describe 'reviews' do
    describe 'GET /reviews' do
      before do
        #create some reviews
      end

      after do
        #delete some reviews
      end

      it "returns all reviews of an author" do
        get "/api/reviews", :author =>  "Knut Hamsun" 
      end

      it "returns reviews of a title given an ISBN" do
        get "/api/reviews", :isbn =>  "9788205367081" 
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["review_title"] == "Is-slottet"
      end

      it "returns reviews og a book given title and author" do
        get "/api/reviews", :author => "Hamsun, Knut", :title => "Sult"
      end

      it "is should be case-insensitive to author & title" do
        #test
      end
    end

    describe 'POST /reviews' do
      after do
        #delete the reivews
      end
    end

    describe 'PUT /reviews' do
      before do
        #create a review
      end

      after do
        #delete review
      end
    end

    describe 'DELETE /reviews' do
      before do
        #recreate review
      end

      after do
        #ensure review deleted
      end
    end
  end
end
