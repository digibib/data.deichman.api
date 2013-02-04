#!/usr/bin/env ruby
# encoding: UTF-8
require "spec_helper"

describe Reviewer do
  context 'find' do
    it "returns all reviewers" do
      r = Reviewer.new.all
      r.count.should >= 1
    end
    
    it "returns a reviewer by name" do
      params = {:name => "anonymous"}
      r = Reviewer.new.find(params)
      r.name.to_s.should == "Anonymous"
    end
  end
  context 'update' do
    it "creates a new reviewer" do
      params = {:api_key => "test", :name => "anonymous"}
      r = Reviewer.new.create(params)
      r.name.to_s.should == "anonymous"
    end
    it "saves a reviewer" do
      params = {:api_key => "test", :name => "dummy"}
      r = Reviewer.new
      r.create(params).save
      r.name.to_s.should == "dummy"
    end
    it "updates reviewer with workplace" do
      params = {:api_key => "test", :name => "dummy"}
      r = Reviewer.new.find(params)
      params[:workplace] = "Eksempelbibliotek"
      r.update(params)
      r.workplace.to_s.should == "Eksempelbibliotek"
    end
    it "deletes a reviewer" do
      params = {:api_key => "test", :name => "dummy"}
      r = Reviewer.new.find(params)
      result = r.delete
      result.should match(/(done)/)
    end  
  
  end
end
