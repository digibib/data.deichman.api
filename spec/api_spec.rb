#!/usr/bin/env ruby
# encoding: UTF-8
require "spec_helper"

describe API do
  include Rack::Test::Methods

  def app
    API
  end

  subject { Class.new(API) }

  shared_context 'review' do
    before(:all)  do
    
      #create dummy review
      post "/api/reviews", {:api_key   => "test", 
          :isbn      => "9788203193538",
          :title     => "A dummy review of Snømannen",
          :teaser    => "Teaser should be short and to the point",
          :text      => "Text should be weighted and both personal and attentive to details...",
          :reviewer  => "anonymous",
          :workplace => "Dummy workplace"}.to_json
      #last_response.status.should == 201
      puts last_response.body
      response = JSON.parse(last_response.body)
      #puts "response: #{response}"
      #response["work"]["author"].should == "Jo Nesbø"
      review = response["work"]["reviews"].first
      review["title"].should == "A dummy review of Snømannen"
      @uri = review["uri"]
    end
    
    after(:all) do
      #delete dummy review
      delete "/api/reviews", {:api_key => "test", :uri => @uri }.to_json
      response = JSON.parse(last_response.body)
      response["result"].should match(/done/)
    end
  end
  
  context 'GET /reviews' do
    include_context 'review'

    it "returns all reviews of an author" do
      
      get "/api/reviews", :author => "Jo Nesbø"
      
      response = JSON.parse(last_response.body)
      response["works"].first["reviews"].count.should >= 1
    end

    it "returns reviews of a title given and ISBN" do
      get "/api/reviews", :isbn =>  "9788203193538"
      response = JSON.parse(last_response.body)
      response["works"].first["reviews"].count.should >= 1
    end

    it "sanitizes ISBN numbers" do
      get "/api/reviews", :isbn =>  "9788203193538"
      response1 = JSON.parse(last_response.body)
      get "/api/reviews", :isbn =>  "978-82-0319-3538(h.)"
      response2 = JSON.parse(last_response.body)
      response1["works"].count.should == response2["works"].count
    end

    it "returns reviews given an URI" do
      get "/api/reviews", :uri => @uri
      puts last_request.inspect
      puts last_response.body
      response = JSON.parse(last_response.body)
      #puts response
      response["works"].first["reviews"].first["title"].should == "A dummy review of Snømannen"
    end

    it "ignores author & title params given an isbn" do
      get "/api/reviews", :isbn   => "9788203193538",
                          :author => "Nesbø, Jo",
                          :title  => "Snømannen"
      response1 = JSON.parse(last_response.body)
      get "/api/reviews", :isbn => "9788203193538"
      response2 = JSON.parse(last_response.body)
      response1["works"].count.should == response2["works"].count
    end

    it "ignores author & title params given an uri" do
      get "/api/reviews", { :uri  => @uri,
                          :author => "Nesbø, Jo",
                          :title  => "Snømannen" }
      response1 = JSON.parse(last_response.body)
      get "/api/reviews", :uri => @uri
      response2 = JSON.parse(last_response.body)
      response1["works"].count.should == response2["works"].count
    end

    it "returns reviews of a book given title and author" do
      get "/api/reviews", :author => "Nesbø, Jo", :title => "Snømannen"
      #last_response.status.should == 200
      response = JSON.parse(last_response.body)
      response["works"].first["reviews"].count.should >= 1
    end

    it "is should be case-insensitive to author & title" do
      get "/api/reviews", :author => "nesbø, jo", :title => "snømannen"
      response1 = JSON.parse(last_response.body)
      get "/api/reviews", :author => "Nesbø, Jo", :title => "Snømannen"
      response2 = JSON.parse(last_response.body)
      response1["works"].count.should == response2["works"].count
    end
    
    it "is returns reviewer and workplace" do
      get "/api/reviews", :uri => @uri
      response = JSON.parse(last_response.body)
      review = response["works"].first["reviews"].first
      review["reviewer"].should  == "anonymous"
      review["workplace"].should == "Dummy workplace"
    end
    
    it "allows case insensitive lookup on reviewer" do
      get "/api/reviews", :reviewer => "anonymous"
      response = JSON.parse(last_response.body)
      review = response["works"].first["reviews"].first
      review["reviewer"].should == "Anonymous"
    end
  end

  context 'PUT /reviews' do
    include_context 'review'

    it "is should demand api_key" do
      put "/api/reviews", {:uri    => @uri,
                          :title   => "An updated review" }.to_json
      #last_response.status.should == 400        
      last_response.body.should match(/missing parameter: api_key/)
    end

    it "is should demand uri of review" do

      put "/api/reviews", {:api_key => "test", 
                          :title    => "An updated review" }.to_json
      last_response.status.should == 400                    
      last_response.body.should match(/missing parameter: uri/)
    end
          
    it "is should update a review" do

      put "/api/reviews", {:api_key => "test",
                          :uri      => @uri,
                          :title    => "An updated review" }.to_json
      #last_response.status.should == 200                    
      response = JSON.parse(last_response.body)
      #puts response
      response["before"]["reviews"].first["title"].should == "A dummy review of Snømannen"
      response["after"]["reviews"].first["title"].should == "An updated review"
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
