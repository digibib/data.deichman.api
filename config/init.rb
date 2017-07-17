#encoding: utf-8
require "rubygems"
require "rdf"
require "rdf/virtuoso"

REPO        = RDF::Virtuoso::Repository.new(
              "http://virtuoso:8890/sparql/",
              :update_uri => "http://virtuoso:8890/sparql-auth/",
              :username => "dba",
              :password => "dba",
              :auth_method => "digest",
              :timeout => 30)

REVIEWGRAPH        = RDF::URI("http://data.deichman.no/reviews")
BOOKGRAPH          = RDF::URI("lsext")
APIGRAPH           = RDF::URI("http://data.deichman.no/sources")
QUERY              = RDF::Virtuoso::Query
BASE_URI           = "http://data.deichman.no"
SECRET_SESSION_KEY = ENV['SECRET_SESSION_KEY']

# load all library files
Dir[File.dirname(__FILE__) + '/../lib/*.rb'].each do |file|
  require file
end
