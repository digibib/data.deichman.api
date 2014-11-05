#!/usr/bin/env ruby
# encoding: UTF-8
require "spec_helper"

describe Reviewer do
  context 'find' do
    it "returns all reviewers" do
      r = Reviewer.new.all
      r.count.should >= 1
    end
    
  end
  context 'update' do
    it "creates a new reviewer" do
      params = {:api_key => "test", :name => "dummy", :userAccount => "test@test.com"}
      r = Reviewer.new.create(params)
      r.name.to_s.should == "dummy"
    end
    it "saves a reviewer" do
      params = {:api_key => "test", :name => "dummy", :userAccount => "test@test.com"}
      r = Reviewer.new.create(params)
      r.save
      r.name.to_s.should == "dummy"
    end
    it "returns a reviewer by account" do
      params = {:userAccount => "test@test.com"}
      r = Reviewer.new.find(params)
      r.name.to_s.should == "dummy"
    end
    it "updates reviewer with workplace homepage" do
      params = {:api_key => "test", :name => "dummy", :userAccount => "test@test.com"}
      r = Reviewer.new.find(params)
      params[:workplaceHomepage] = "http://example.library.com"
      r.update(params)
      r.workplaceHomepage.to_s.should == "http://example.library.com"
    end
    it "updates reviewer name" do
      params = {:api_key => "test", :userAccount => "test@test.com"}
      r = Reviewer.new.find(params)
      params[:name] = "dummy2"
      r.update(params)
      r.name.to_s.should == "dummy2"
    end
    it "deletes a reviewer" do
      params = {:api_key => "test", :userAccount => "test@test.com"}
      r = Reviewer.new.find(params)
      result = r.delete(params)
      result.should match(/(done)/)
    end  
  
  end
end
