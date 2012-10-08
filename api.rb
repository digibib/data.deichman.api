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
      uri           = params[:uri] ? params[:uri] : :review

      query = QUERY.select.distinct.where(
        [:review, RDF.type, RDF::REV.Review, :context => REVIEWGRAPH],
        [:review, RDF::DEICHMAN.basedOnManifestation, :book, :context => REVIEWGRAPH],
        [:review, RDF::DC.issued, :issued, :context => REVIEWGRAPH],
        [:book, RDF::BIBO.isbn, isbn, :context => BOOKGRAPH],
        [:book, RDF::DC.title, :book_title, :context => BOOKGRAPH],
        [:book, RDF::DC.creator, :author, :context => BOOKGRAPH],
        [:author, RDF::FOAF.name, :author_name, :context => BOOKGRAPH]
        )
      query.optional([:review, RDF::REV.title, :review_title, :context => REVIEWGRAPH])
      query.optional([:review, RDF::DC.abstract, :review_abstract, :context => REVIEWGRAPH])
      query.optional([:review, RDF::REV.text, :review_text, :context => REVIEWGRAPH])
      query.optional([:review, RDF::DC.source, :review_source, :context => REVIEWGRAPH])
      query.optional([:review, RDF::REV.reviewer, :reviewer, :context => REVIEWGRAPH])
      query.optional([:review, RDF::DC.publisher, :review_publisher, :context => REVIEWGRAPH])
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
