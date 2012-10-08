#encoding: utf-8

require "bundler/setup"
require "grape"
require "rdf/virtuoso"
require "./vocabularies.rb"


repository = YAML::load(File.open("config/repository.yml"))
REPO = RDF::Virtuoso::Repository.new(
              repository["sparql_endpoint"],
              :update_uri => repository["sparul_endpoint"],
              :username => repository["username"],
              :password => repository["password"],
              :auth_method => repository["auth_method"])

QUERY       = RDF::Virtuoso::Query
REVIEWGRAPH = RDF::URI('http://data.deichman.no/reviews')
BOOKGRAPH = RDF::URI('http://data.deichman.no/books')

module Grape
  class Endpoint
    def params
      return @params if @params
      params = request.params
      params.merge!(request.env['action_dispatch.request.request_parameters'] || {})
      params.merge!(request.env['rack.routing_args'] || {})
      @params = params
    end
  end
end

class API < Grape::API
  prefix 'api'
  format :json
  default_format :json

  resource :reviews do
    desc "returns reviews"
    get "/" do
      isbn          = params[:isbn] ? "#{params[:isbn].strip.gsub(/[^0-9]/, '')}" : :isbn
      author_search = params[:author] ? params[:author].gsub(/[[:punct:]]/, '').split(" ") : nil
      title_search  = params[:title] ? params[:title].gsub(/[[:punct:]]/, '').split(" ") : nil
      uri           = params[:uri] ? RDF::URI(params[:uri]) : :uri

      query = QUERY.select(:uri, :book_title, :issued, :review_title, :review_abstract, :review_text, :review_source, :reviewer, :review_publisher)
      query.group_digest(:isbn, ', ', 1000, 1)
      query.group_digest(:author, ', ', 1000, 1)
      query.distinct.where(
        [uri, RDF.type, RDF::REV.Review, :context => REVIEWGRAPH],
        [uri, RDF::DEICHMAN.basedOnManifestation, :book, :context => REVIEWGRAPH],
        [uri, RDF::DC.issued, :issued, :context => REVIEWGRAPH],
        [:book, RDF::BIBO.isbn, isbn, :context => BOOKGRAPH],
        [:book, RDF::DC.title, :book_title, :context => BOOKGRAPH],
        [:book, RDF::DC.creator, :author_id, :context => BOOKGRAPH],
        [:author_id, RDF::FOAF.name, :author, :context => BOOKGRAPH]
        )
      query.optional([uri, RDF::REV.title, :review_title, :context => REVIEWGRAPH])
      query.optional([uri, RDF::DC.abstract, :review_abstract, :context => REVIEWGRAPH])
      query.optional([uri, RDF::REV.text, :review_text, :context => REVIEWGRAPH])
      query.optional([uri, RDF::DC.source, :review_source, :context => REVIEWGRAPH])
      query.optional([uri, RDF::REV.reviewer, :reviewer_id, :context => REVIEWGRAPH],
                     [:reviewer_id, RDF::FOAF.name, :reviewer, :context => REVIEWGRAPH])
      query.optional([uri, RDF::DC.publisher, :publisher_id, :context => REVIEWGRAPH],
                     [:publisher_id, RDF::FOAF.name, :review_publisher, :context => REVIEWGRAPH])
      query.filter('lang(?review_text) != "nn"')

      if author_search
        author_search.each do |author|
          query.filter("regex(?author_name, \"#{author}\", \"i\")")
        end
      end

      if title_search
        title_search.each do |title|
          query.filter("regex(?book_title, \"#{title}\", \"i\")")
        end
      end
      query.limit(50)
#puts query
      solutions = REPO.select(query)
      reviews = []
      solutions.each do |solution|
        s = {}
        solution.each_binding { |name, value| s[name] = value.to_s }
        reviews.push(s)
      end

      header['Content-Type'] = 'application/json; charset=utf-8'
      { :reviews => reviews }
    end

    desc "creates a review"
    post "/" do
      "Hello world"
    end

    desc "updates a review"
    put "/" do
      "Hello world"
    end

    desc "deletes a review"
    delete "/" do
      "Hello world"
    end
  end
end
