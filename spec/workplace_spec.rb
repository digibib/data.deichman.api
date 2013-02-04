#!/usr/bin/env ruby
# encoding: UTF-8
require "spec_helper"

describe Workplace do
  context 'find' do
    it "returns all workplaces" do
      w = Workplace.new.all
      w.count.should >= 1
    end
    
    it "returns a workplace by name" do
      params = {:workplace => "Eksempelbibliotek"}
      w = Workplace.new.find(params)
      w.prefLabel.to_s.should == "Eksempelbibliotek"
    end
  end
  context 'update' do
    it "creates a new workplace" do
      params = {:api_key => "test", :workplace => "dummy"}
      w = Workplace.new.create(params)
      w.prefLabel.to_s.should == "dummy"
      w.uri.to_s.should       == "http://data.deichman.no/workplace/dummy"
    end
    it "saves a workplace" do
      params = {:api_key => "test", :workplace => "dummy"}
      w = Workplace.new.create(params)
      w.save
      w.prefLabel.to_s.should == "dummy"
    end
    it "updates a workplace" do
      params = {:api_key => "test", :workplace => "dummy"}
      w = Workplace.new.find(params)
      w.prefLabel = "dummy2"
      w.save
      w.prefLabel.to_s.should == "dummy2"
    end
    it "deletes a workplace" do
      params = {:api_key => "test", :workplace => "dummy2"}
      w = Workplace.new.find(params)
      result = w.delete
      result.should match(/(done)/)
    end
  end
end
