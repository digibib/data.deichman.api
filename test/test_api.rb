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
        @uri = "http://data.deichman.no/test/review/id_123456"
      end

      it "returns all reviews of an author" do
        get "/api/reviews", :author =>  "Jo Nesbø"
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["works"].count.must_be  :>=, 1
      end

      it "returns reviews of a title given and ISBN" do
        get "/api/reviews", :isbn =>  "9788203193538"
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["works"].count.must_be  :>=, 1
      end

      it "sanitizes ISBN numbers" do
        get "/api/reviews", :isbn =>  "9788203193538"
        response1 = JSON.parse(last_response.body)
        get "/api/reviews", :isbn =>  "978-82-0319-3538(h.)"
        response2 = JSON.parse(last_response.body)
        response1["works"].must_equal response2["works"]
      end

      it "returns reviews given an URI" do
        get "/api/reviews", :uri => "#{@uri}"
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["works"].first["reviews"].first["title"].must_equal "Testreview"
      end

      it "ignores author & title params given an isbn" do
        get "/api/reviews", :isbn => "9788203193538",
                            :author => "Nesbø, Jo",
                            :title => "Snømannen"
        response1 = JSON.parse(last_response.body)
        get "/api/reviews", :isbn => "9788203193538"
        response2 = JSON.parse(last_response.body)
        response1["works"].must_equal response2["works"]
      end

      it "ignores author & title params given an uri" do
        get "/api/reviews", :uri => "#{@uri}",
                            :author => "Nesbø, Jo",
                            :title => "Snømannen"
        response1 = JSON.parse(last_response.body)
        get "/api/reviews", :uri => "#{@uri}"
        response2 = JSON.parse(last_response.body)
        response1["works"].must_equal response2["works"]
      end

      it "returns reviews of a book given title and author" do
        get "/api/reviews", :author => "Nesbø, Jo", :title => "Snømannen"
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["works"].first["reviews"].count.must_be  :>=, 1
      end

      it "is should be case-insensitive to author & title" do
        get "/api/reviews", :author => "nesbø, jo", :title => "snømannen"
        response1 = JSON.parse(last_response.body)
        get "/api/reviews", :author => "Nesbø, Jo", :title => "Snømannen"
        response2 = JSON.parse(last_response.body)
        response1["works"].must_equal response2["works"]
      end
    end

    describe 'POST /reviews' do
      it "should create a review" do
        post "/api/reviews", {:api_key  => "test",
                             :isbn     => "9788203193538",
                             :title    => "A dummy review of Snømannen",
                             :teaser   => "Teaser should be short and to the point",
                             :text     => "Text should be weighted and both personal and attentive to details..."}.to_json
        last_response.status.must_equal 201
        response = JSON.parse(last_response.body)
        response["work"]["reviews"].first["title"].must_equal "A dummy review of Snømannen"
        @uri = response["work"]["reviews"].first["uri"]
      end

      after do
        #delete the reivew
        delete "/api/reviews", {:api_key  => "test",
                               :uri      => "#{@uri}"}.to_json
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["result"].must_match(/done/)
      end
    end

    describe 'PUT /reviews' do
      before do
        #create review
        post "/api/reviews", {:api_key  => "test",
                             :isbn     => "9788203193538",
                             :title    => "A dummy review of Snømannen",
                             :teaser   => "Teaser should be short and to the point",
                             :text     => "Text should be weighted and both personal and attentive to details..."}.to_json
      end

      after do
        #delete the reivew
        delete "/api/reviews", {:api_key  => "test",
                               :uri      => "#{@uri}"}.to_json
      end

      it "is should demand api_key" do
        put "/api/reviews", {:uri     => "#{@uri}",
                            :title   => "An updated review"}.to_json
        last_response.status.must_equal 400
        last_response.body.must_match (/missing parameter: api_key/)
      end

      it "is should demand uri of review" do
        put "/api/reviews", {:api_key => "test",
                            :title   => "An updated review"}.to_json
        last_response.status.must_equal 400
        last_response.body.must_match (/missing parameter: uri/)
      end

      it "is should update a review" do
        put "/api/reviews", {:api_key => "test",
                            :uri     => "#{@uri}",
                            :title   => "An updated review"}.to_json
        last_response.status.must_equal 200
        response = JSON.parse(last_response.body)
        response["before"].first["reviews"].first["title"].must_equal "A dummy review of Snømannen"
        response["after"]["reviews"].first["title"].must_equal "An updated review"
      end

    end

    describe 'DELETE /api/reviews' do
      before do
        #recreate review
      end

      after do
        #ensure review deleted
      end
    end
  end
end
