#!/usr/bin/env ruby
# encoding: UTF-8
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
        #create some dummy reviews
      end

      after do
        #delete some dummy reviews
      end

      it "returns all reviews of an author" do
        get "/api/reviews", :author =>  "Knut Hamsun"
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["reviews"].count.must_be  :>=, 5
      end

      it "returns reviews of a title given and ISBN" do
        get "/api/reviews", :isbn =>  "9788205367081"
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["reviews"].first["review_title"].must_equal "Is-slottet"
      end

      it "sanitizes ISBN numbers" do
        get "/api/reviews", :isbn =>  "9788205367081"
        response1 = JSON.parse(last_response.body)
        get "/api/reviews", :isbn =>  "978-82-05-36708-1(h.)"
        response2 = JSON.parse(last_response.body)
        response1.must_equal response2
      end

      it "returns reviews given an URI" do
        get "/api/reviews", :uri => "http://data.deichman.no/bookreviews/onskebok/id_1025"
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["reviews"].first["book_title"].must_equal "Is-slottet"
      end

      it "ignores author & title params given an isbn" do
        get "/api/reviews", :isbn => "9788205367081",
                            :author => "Ibsen, Henrik",
                            :title => "En folkefiende"
        response1 = JSON.parse(last_response.body)
        get "/api/reviews", :isbn => "9788205367081"
        response2 = JSON.parse(last_response.body)
        response1.must_equal response2
      end

      it "ignores author & title params given an uri" do
        get "/api/reviews", :uri => "http://data.deichman.no/bookreviews/onskebok/id_1025",
                            :author => "Ibsen, Henrik",
                            :title => "En folkefiende"
        response1 = JSON.parse(last_response.body)
        get "/api/reviews", :uri => "http://data.deichman.no/bookreviews/onskebok/id_1025"
        response2 = JSON.parse(last_response.body)
        response1.must_equal response2
      end

      it "returns reviews of a book given title and author" do
        get "/api/reviews", :author => "Hamsun, Knut", :title => "Sult"
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["reviews"].first["book_title"].must_equal "Sult"
      end

      it "is should be case-insensitive to author & title" do
        get "/api/reviews", :author => "hamsun, knut", :title => "sult"
        response1 = JSON.parse(last_response.body)
        get "/api/reviews", :author => "Hamsun, Knut", :title => "Sult"
        response2 = JSON.parse(last_response.body)
        response1.must_equal response2
      end
    end

    describe 'POST /reviews' do
      it "is should create a review" do
        post "/api/reviews", :api_key  => "deichmankey", 
                             :isbn     => "9788205367081",
                             :title    => "sulten",
                             :teaser   => "trenger no mat",
                             :text     => "boka for deg hvis du trenger no fôr, kjapt!"
        response = JSON.parse(last_response.body)
        response["review"].first["book_title"].must_equal "Sult"
      end
        
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
