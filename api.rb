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
QUERY  = RDF::Virtuoso::Query
DEFAULT_GRAPH = RDF::URI('http://data.deichman.no/bookreviews')

#sanitize_isbn: isbn.strip.gsub(/\s+|-/, '')
isbn ="9788243006218"
query = QUERY.select([])

class API < Grape::API
  prefix 'api'

  resource :reviews do
    desc "returns reviews"
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