#encoding: utf-8
# read configuration file into constants
repository  = YAML::load(File.open("config/repository.yml"))
REPO        = RDF::Virtuoso::Repository.new(
              repository["sparql_endpoint"],
              :update_uri => repository["sparul_endpoint"],
              :username => repository["username"],
              :password => repository["password"],
              :auth_method => repository["auth_method"])

REVIEWGRAPH = RDF::URI(repository["reviewgraph"])
BOOKGRAPH   = RDF::URI(repository["bookgraph"])
APIGRAPH    = RDF::URI(repository["apigraph"])
QUERY       = RDF::Virtuoso::Query
