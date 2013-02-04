#!/usr/bin/env ruby
# encoding: UTF-8
require "spec_helper"

describe Source do
  context 'find' do
    it "returns all reviewers" do
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
 
end
