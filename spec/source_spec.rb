#!/usr/bin/env ruby
# encoding: UTF-8
require "spec_helper"

describe Source do
  context 'find' do
    it "returns all sources" do
      s = Source.new.all
      s.count.should >= 1
    end
    
    it "returns a source with api_key as parameter" do
      params = {:api_key => "test"}
      s = Source.new.find_by_apikey(params[:api_key])
      s.name.to_s.should == "Testkilde for Testing"
    end
  end
  context 'autoincrement' do
    it "generates an unique reviewer uri from source " do
      params = {:api_key => "test"}
      source = Source.new.find_by_apikey(params[:api_key])
      id = source.autoincrement_resource(source.uri.to_s)
      id.to_s.should match(/http:\/\/data.deichman.no\/test\/review\//)
    end
  end
  context 'update' do
  
    it "fails to create duplicate source" do
      params = {:name => "test"}
      s = Source.new.create(params)
      s.should == "source must be unique"
    end
    it "creates a new source" do
      params = {:name => "dummy", :homepage => "dummyhomepage"}
      s = Source.new.create(params)
      s.name.to_s.should == "dummy"
      s.uri.to_s.should  == "http://data.deichman.no/source/dummy"
    end
    it "saves a source" do
      params = {:name => "dummy", :homepage => "dummyhomepage"}
      s = Source.new.create(params)
      s.save
      s.uri.to_s.should  == "http://data.deichman.no/source/dummy"
    end
    it "updates a source" do
      s = Source.new.find(:uri => "http://data.deichman.no/source/dummy")
      s.update :name => "dummy2"
      s.save
      s.name.to_s.should == "dummy2"
    end
    it "deletes a source" do
      s = Source.new.find(:uri => "http://data.deichman.no/source/dummy")
      result = s.delete
      result.should match(/(done)/)
    end
  end 
end
