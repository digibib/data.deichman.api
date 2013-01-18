#!/usr/bin/env ruby
# encoding: UTF-8
require "spec_helper"

def app
  API
end

describe API do
  include Rack::Test::Methods

  describe 'GET /reviews' do
    before(:all)  do

      #create dummy review
      post "/api/reviews", MultiJson.encode({
          :api_key  => "test", 
          :isbn     => "9788203193538",
          :title    => "A dummy review of Snømannen",
          :teaser   => "Teaser should be short and to the point",
          :text     => "Text should be weighted and both personal and attentive to details...",
          :reviewer => "Test Testesen"}),
          {'CONTENT_TYPE' => 'application/json'}
      #last_response.status.should == 201
      
      response = JSON.parse(last_response.body)
      #puts "response: #{response}"
      #response["work"]["author"].should == "Jo Nesbø"
      review = response["work"]["reviews"].first
      review["title"].should == "A dummy review of Snømannen"
      @uri = review["uri"]
    end

    after(:all) do
      #delete dummy review
      delete "/api/reviews", MultiJson.encode({
          :api_key  => "test", 
          :uri      => "#{@uri}"}),
          {'CONTENT_TYPE' => 'application/json'}
      response = JSON.parse(last_response.body)
      response["result"].should match(/done/)
    end

    it "returns all reviews of an author" do
      get "/api/reviews", :author =>  "Jo Nesbø"
      
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
      get "/api/reviews", :uri => "#{@uri}"
      response = JSON.parse(last_response.body)
      #puts response
      response["works"].first["reviews"].first["title"].should == "A dummy review of Snømannen"
    end

    it "ignores author & title params given an isbn" do
      get "/api/reviews", :isbn => "9788203193538",
                          :author => "Nesbø, Jo",
                          :title => "Snømannen"
      response1 = JSON.parse(last_response.body)
      get "/api/reviews", :isbn => "9788203193538"
      response2 = JSON.parse(last_response.body)
      response1["works"].count.should == response2["works"].count
    end

    it "ignores author & title params given an uri" do
      get "/api/reviews", { :uri => "#{@uri}",
                          :author => "Nesbø, Jo",
                          :title => "Snømannen" }
      response1 = JSON.parse(last_response.body)
      get "/api/reviews", :uri => "#{@uri}"
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
  end

  describe 'POST /reviews' do
    it "should create a review" do
      #create the review
      post "/api/reviews", MultiJson.encode({:api_key  => "test", 
                           :isbn     => "9788203193538",
                           :title    => "A dummy review of Snømannen",
                           :teaser   => "Teaser should be short and to the point",
                           :text     => "Text should be weighted and both personal and attentive to details..."}),
                           {'CONTENT_TYPE' => 'application/json'}
      last_response.status.should == 201
      response = JSON.parse(last_response.body)
      review = response["work"]["reviews"].first
      review["title"].should == "A dummy review of Snømannen"
      uri = review["uri"]
      
      # for some curioius reason not working...
      #delete the review
      #delete "/api/reviews", MultiJson.encode({
      #    :api_key  => "test", 
      #    :uri      => "#{uri}"}),
      #    {'CONTENT_TYPE' => 'application/json'}
      #puts last_request.inspect
      #last_response.status.should == 200
      #response = JSON.parse(last_response.body)
      #response["result"].should match(/done/)
    end
  end

  describe 'PUT /reviews' do
    before(:all) do

      #create review
      post "/api/reviews", {:api_key  => "test", 
                           :isbn     => "9788203193538",
                           :title    => "A dummy review of Snømannen",
                           :teaser   => "Teaser should be short and to the point",
                           :text     => "Text should be weighted and both personal and attentive to details..."}.to_json,
                           {'CONTENT_TYPE' => 'application/json'}
      last_response.status.should == 201
      response = JSON.parse(last_response.body)
      review = response["work"]["reviews"].first
      review["title"].should == "A dummy review of Snømannen"
      @uri = review["uri"]
    end

    after(:all) do

      #delete the review
      delete "/api/reviews", MultiJson.encode({:api_key  => "test", 
                             :uri      => "#{@uri}"}),
                             {'CONTENT_TYPE' => 'application/json'}
      #last_response.status.should == 200
      response = JSON.parse(last_response.body)
      response["result"].should match(/done/)
    end

    it "is should demand api_key" do

      put "/api/reviews", MultiJson.encode({:uri     => "#{@uri}",
                          :title   => "An updated review"}),
                          {'CONTENT_TYPE' => 'application/json'}
      #last_response.status.should == 400        
      last_response.body.should match(/missing parameter: api_key/)
    end

    it "is should demand uri of review" do

      put "/api/reviews", MultiJson.encode({:api_key => "test", 
                          :title   => "An updated review"}),
                          {'CONTENT_TYPE' => 'application/json'}
      last_response.status.should == 400                    
      last_response.body.should match(/missing parameter: uri/)
    end
          
    it "is should update a review" do

      put "/api/reviews", MultiJson.encode({:api_key => "test",
                          :uri     => "#{@uri}",
                          :title   => "An updated review"}),
                          {'CONTENT_TYPE' => 'application/json'}
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
