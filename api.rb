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

#sanitize_isbn: isbn.strip.gsub(/\s+|-/, '')
isbn ="9788205367081"

class API < Grape::API
  prefix 'api'
  format :json
  
  resource :reviews do
    desc "returns reviews"
    get "/" do
      if params[:isbn]
        query = QUERY.select.distinct.where(
          [:review, RDF.type, RDF::REV.Review, :context => REVIEWGRAPH],
          [:review, RDF::DEICHMAN.basedOnManifestation, :book, :context => REVIEWGRAPH],
          [:review, RDF::DC.issued, :issued, :context => REVIEWGRAPH],
          [:book, RDF::BIBO.isbn, "#{params[:isbn]}", :context => BOOKGRAPH],
          [:book, RDF::DC.title, :book_title, :context => BOOKGRAPH]
          )
        query.optional([:review, RDF::REV.title, :review_title, :context => REVIEWGRAPH])
        query.optional([:review, RDF::DC.abstract, :review_abstract, :context => REVIEWGRAPH])
        query.optional([:review, RDF::REV.text, :review_text, :context => REVIEWGRAPH])
        query.optional([:review, RDF::DC.source, :review_source, :context => REVIEWGRAPH])
        query.optional([:review, RDF::REV.reviewer, :reviewer, :context => REVIEWGRAPH])
        query.optional([:review, RDF::DC.publisher, :review_publisher, :context => REVIEWGRAPH])
        query.filter('lang(?review_text) != "nn"')
        query.limit(50)
        solutions = REPO.select(query)
        { :reviews => solutions.bindings.to_json }
      end
      
    end

    get "/" do
      "Hello world"
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
