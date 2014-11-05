#!/usr/bin/env ruby
# coding: utf-8

require "spec_helper"

describe API do
  include Rack::Test::Methods

  def app
    API::Root
  end
  
  describe Review do
    describe 'POST /reviews' do
      it "creates a review" do
        #create dummy review
        post "/api/reviews", {
            :api_key   => "test", 
            :isbn      => "9788203193538",
            :title     => "A dummy review of Snømannen",
            :teaser    => "Teaser should be short and to the point",
            :text      => "Text should be weighted and both personal and attentive to details...",
            :reviewer  => "test@test.com",
            :workplace => "Dummy workplace"}.to_json
        #last_response.status.should == 201
        result = JSON.parse(last_response.body)
        #puts "response: #{result}"
        #response["work"]["author"].should == "Jo Nesbø"
        result["works"].first["reviews"].first["title"].should == "A dummy review of Snømannen"
      end
    end
    
    describe 'GET /reviews' do
    
      it "returns all reviews of an author" do
        get "/api/reviews", :author => "Jo Nesbø"
        response = JSON.parse(last_response.body)
        response["works"].first["reviews"].count.should >= 1
      end
  
      it "returns reviews of a title given and ISBN" do
        get "/api/works", :isbn =>  "9788203193538", :reviews => true
        response = JSON.parse(last_response.body)
        response["works"].first["reviews"].count.should >= 1
      end
  
      it "sanitizes ISBN numbers" do
        get "/api/works", :isbn =>  "9788203193538", :reviews => true
        response1 = JSON.parse(last_response.body)
        get "/api/works", :isbn =>  "978-82-0319-3538(h.)", :reviews => true
        response2 = JSON.parse(last_response.body)
        response1["works"].count.should == response2["works"].count
      end
  
      it "returns reviews given a URI" do
        get "/api/works", :isbn =>  "9788203193538", :reviews => true, :order_by => 'created'
        response = JSON.parse(last_response.body)
        uri = response["works"].first["reviews"].first["uri"]
        
        get "/api/reviews", :uri => uri
        puts last_request.inspect
        puts last_response.body
        response = JSON.parse(last_response.body)
        #puts response
        response["works"].first["reviews"].first["title"].should == "A dummy review of Snømannen"
      end
  
      it "ignores author & title params given an isbn" do
        get "/api/works",   :isbn   => "9788203193538",
                            :author => "Nesbø, Jo",
                            :title  => "Snømannen",
                            :reviews => true
        response1 = JSON.parse(last_response.body)
        puts response1.inspect
        get "/api/works", :isbn =>  "9788203193538", :reviews => true
        response2 = JSON.parse(last_response.body)
        response1["works"].count.should == response2["works"].count
      end
  
      it "ignores author & title params given a uri" do
        get "/api/reviews", :isbn => "9788203193538", :order_by => 'created'
        response = JSON.parse(last_response.body)
        uri = response["works"].first["reviews"].first["uri"]
        
        get "/api/reviews", { :uri  => uri,
                            :author => "Nesbø, Jo",
                            :title  => "Snømannen" }
        response1 = JSON.parse(last_response.body)
        get "/api/reviews", :uri => uri
        response2 = JSON.parse(last_response.body)
        response1["works"].count.should == response2["works"].count
      end
  
      it "returns reviews of a book given title and author" do
        get "/api/reviews", :author => "Nesbø, Jo", :title => "Snømannen"
        #last_response.status.should == 200
        response = JSON.parse(last_response.body)
        response["works"].first["reviews"].count.should >= 1
      end
  
      it "should be case-insensitive to author & title" do
        get "/api/reviews", :author => "nesbø, jo", :title => "snømannen"
        response1 = JSON.parse(last_response.body)
        get "/api/reviews", :author => "Nesbø, Jo", :title => "Snømannen"
        response2 = JSON.parse(last_response.body)
        response1["works"].count.should == response2["works"].count
      end
      
      it "is returns reviewer name and uri" do
        get "/api/reviews", :isbn => "9788203193538", :order_by => 'created'
        response = JSON.parse(last_response.body)
        uri = response["works"].first["reviews"].first["uri"]
        
        get "/api/reviews", :uri => uri
        response = JSON.parse(last_response.body)
        review = response["works"].first["reviews"].first
        review["reviewer"]["name"]  == "Anonymous"
        review["reviewer"]["uri"] == "http://data.deichman.no/reviewer/id_0"
      end
      
      it "allows lookup on reviewer" do
        get "/api/reviews", :reviewer => "http://data.deichman.no/reviewer/id_0"
        response = JSON.parse(last_response.body)
        review = response["works"].first["reviews"].first
        review["reviewer"]["uri"].should == "http://data.deichman.no/reviewer/id_0"
      end
    end
  
    describe 'PUT /reviews' do
      it "should demand api_key" do
        get "/api/works", :isbn => "9788203193538", :order_by => 'created', :reviews => true
        response = JSON.parse(last_response.body)
        uri = response["works"].first["reviews"].first["uri"]
        put "/api/reviews", {:uri    => uri,
                            :title   => "An updated review" }.to_json
        last_response.status.should == 500
        last_response.body.should match(/missing parameter: api_key/)
      end
  
      it "should demand uri of review" do
  
        put "/api/reviews", {:api_key => "test", 
                            :title    => "An updated review" }.to_json
        last_response.status.should == 500
        last_response.body.should match(/missing parameter: uri/)
      end
            
      it "should update a review" do
        get "/api/works", :isbn => "9788203193538", :order_by => 'created', :reviews => true
        response = JSON.parse(last_response.body)
        uri = response["works"].first["reviews"].first["uri"]
            
        put "/api/reviews", {:api_key => "test",
                            :uri      => uri,
                            :title    => "An updated review" }.to_json
        last_response.status.should == 200 
        response = JSON.parse(last_response.body)
        response["works"].first["reviews"].first["title"].should == "An updated review"
      end
      
    end
  
    describe 'DELETE /api/reviews' do
  
      it "should delete review" do
        get "/api/works", :isbn => "9788203193538", :order_by => 'created', :reviews => true
        response = JSON.parse(last_response.body)
        uri = response["works"].first["reviews"].first["uri"]
            
        #delete dummy review
        delete "/api/reviews", {:api_key => "test", :uri => uri }.to_json
        response = JSON.parse(last_response.body)
        response["result"].should match(/done/)
      end
    end
  end
  
  describe Reviewer do

    it "should demand correct api_key when creating a user" do
      post "/api/users", {:accountName => "test@test.com", :api_key => "bogus"}.to_json
      response = JSON.parse(last_response.body)
      response["error"].should match(/(not a valid api key)/)
    end

    it "should create a user" do
      post "/api/users", {:accountName => "test@test.com", :api_key => "test", :name => "dummy"}.to_json
      last_response.status.should == 201
      response = JSON.parse(last_response.body)
      response["reviewer"]["userAccount"]["accountName"].should == "test@test.com"
    end
    
    it "should get all users" do
      get "/api/users"
      last_response.status.should == 200
      response = JSON.parse(last_response.body)
      response["reviewers"].count.should >= 1
    end
    
    it "should return a specific user" do
      get "/api/users", :accountName => "test@test.com"
      last_response.status.should == 200
      response = JSON.parse(last_response.body)
      response["reviewer"]["userAccount"]["accountName"].should == "test@test.com"
    end

    it "should update a user" do
      get "/api/users", :accountName => "test@test.com"
      response = JSON.parse(last_response.body)
      uri = response["reviewer"]["uri"]

      put "/api/users", {:uri => uri, :api_key => "test", :name => "modified dummyuser"}.to_json
      response = JSON.parse(last_response.body)
      response["reviewer"]["name"].should == "modified dummyuser"
    end

    it "should delete a user" do
      get "/api/users", :accountName => "test@test.com"
      response = JSON.parse(last_response.body)
      uri = response["reviewer"]["uri"]
      
      delete "/api/users", {:uri => uri, :api_key => "test"}.to_json
      last_response.status.should == 200
      response = JSON.parse(last_response.body)
      response["result"].should match(/done/)
    end         
  end
end
