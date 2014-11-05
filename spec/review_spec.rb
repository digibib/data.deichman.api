#!/usr/bin/env ruby
# encoding: UTF-8
require "spec_helper"

describe Review do
  context 'find' do
    it "returns all reviews" do
      reviews = Review.new.all
      reviews.count.should >= 1
    end
    it "accepts limit and order params" do
      reviews = Review.new.all :limit=>5, :offset=>0, :order_by=>"author", :order=>"desc"
      reviews.count.should >= 1
    end
    
    it "returns a specific review" do
      reviews = Review.new.find :uri => "http://data.deichman.no/test/review/id_0"
      reviews.first.uri.to_s.should == "http://data.deichman.no/test/review/id_0"
    end
  end

  context 'create/update' do
    it "creates a review" do
      params = {
          :api_key   => "test", 
          :isbn      => "9788203193538",
          :title     => "A dummy review of Snømannen",
          :teaser    => "Teaser should be short and to the point",
          :text      => "Text should be weighted and both personal and attentive to details...",
          :reviewer  => "test@test.com",
          :workplace => "Dummy workplace"
          }
      review = Review.new.create(params)
      review.source.to_s.should == "http://data.deichman.no/source/test"
    end
    
    it "saves a review" do
      params = {
          :api_key   => "test", 
          :isbn      => "9788203193538",
          :title     => "A dummy review of Snømannen",
          :teaser    => "Teaser should be short and to the point",
          :text      => "Text should be weighted and both personal and attentive to details...",
          :reviewer  => "test@test.com",
          :workplace => "Dummy workplace"
          }
      review = Review.new.create(params)
      review.save
      review.source.to_s.should == "http://data.deichman.no/source/test"
    end
  end
end
