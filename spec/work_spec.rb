#!/usr/bin/env ruby
# encoding: UTF-8
require "spec_helper"

describe Work do
  context 'find' do
    it "returns works by isbn" do
      params = {:isbn => "9788203193538"}
      works = Work.new.find(params)
      puts works.inspect
      works.first.authors.first.name.to_s.should == "Jo Nesbø"
    end
    
    it "returns works by author" do
      params = {:author_name => "Jo Nesbø"}
      works = Work.new.find(params)
      puts works.inspect
      works.first.authors.first.name.to_s.should == "Jo Nesbø"
    end
    
    it "returns works by uri" do
      params = {:uri => "http://data.deichman.no/work/x18370200_snoemannen"}
      works = Work.new.find(params)
      puts works.inspect
      works.first.authors.first.name.to_s.should == "Jo Nesbø"
    end
  end
end
