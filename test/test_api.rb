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
        #create some reviews
      end

      after do
        #delete some reviews
      end

      it "returns all reviews of an author" do
        get "/api/reviews", :author =>  "Knut Hamsun"
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["reviews"]["review"].count.must_equal 12
      end

      it "returns reviews of a title given an ISBN" do
        get "/api/reviews", :isbn =>  "9788205367081"
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["reviews"]["review_title"].first.must_equal "Is-slottet"
      end

      it "sanitizes ISBN numbers" do
        get "/api/reviews", :isbn =>  "9788205367081"
        response1 = JSON.parse(last_response.body)
        get "/api/reviews", :isbn =>  "978-82-05-36708-1(h.)"
        response2 = JSON.parse(last_response.body)
        response1.must_equal response2
      end

      it "returns reviews of a book given title and author" do
        get "/api/reviews", :author => "Hamsun, Knut", :title => "Sult"
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["reviews"]["book_title"].first.must_equal "Sult"
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
