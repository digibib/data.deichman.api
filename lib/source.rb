#encoding: utf-8
require 'securerandom'

Source = Struct.new(:uri, :name, :homepage, :api_key)
class Source
  def all
    query = QUERY.select(:uri, :name, :homepage, :api_key).from(APIGRAPH)
    query.where(
      [:uri, RDF.type, RDF::FOAF.Document], 
      [:uri, RDF::FOAF.name, :name],
      [:uri, RDF::DEICHMAN.apikey, :api_key])
    query.optional([:uri, RDF::FOAF.homepage, :homepage])
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty?
    sources = []
    solutions.each do |s|
      source = s.to_hash.to_struct("Source")
      source.api_key = nil
      sources << source
    end
    sources
  end

  def find(params)
    return nil unless params[:uri] || params[:name]
    selects = [:uri, :name, :homepage, :api_key]
    api = Hashie::Mash.new(:uri => :uri, :name => :name)
    params[:uri] = RDF::URI(params[:uri]) if params[:uri]
    api.merge!(params)
    # remove variable from selects array if variable given as param
    #selects.delete_if {|s| params[s]}
    
    query = QUERY.select(*selects).from(APIGRAPH)
    # source by uri
    api[:uri].is_a?(Symbol) ?
      query.where([api[:uri], RDF.type, RDF::FOAF.Document], [api[:uri], RDF::FOAF.name, api[:name]], [api[:uri], RDF::DEICHMAN.apikey, :api_key]) :
      query.where([api[:uri], RDF.type, RDF::FOAF.Document], [api[:uri], RDF::FOAF.name, api[:name]], [api[:uri], RDF::DEICHMAN.apikey, :api_key], [:uri, RDF::FOAF.name, api[:name]])
    query.optional([api[:uri], RDF::FOAF.homepage, :homepage])
    query.limit(1)
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty?
    
    # populate Source Struct    
    self.members.each {|name| self[name] = solutions.first[name] }  
    self
  end
    
  def find_by_apikey(api_key)
    # fetch source by api key in protected graph
    # each source needs three statements: 
    # <source> a foaf:Document ;
    #          foaf:name "Label" ;
    #          deichman:apikey "apikey" .    
    query = QUERY.select(:uri, :name, :homepage).from(APIGRAPH)
    query.where(
      [:uri, RDF.type, RDF::FOAF.Document], 
      [:uri, RDF::FOAF.name, :name],
      [:uri, RDF::DEICHMAN.apikey, "#{api_key}"])
    query.optional([:uri, RDF::FOAF.homepage, :homepage])
    query.limit(1)
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty?
    
    # populate Source Struct    
    self.members.each {|name| self[name] = solutions.first[name] }  
    self.api_key = api_key
    self
  end

  def autoincrement_resource(source, resource = "review")
    # This method uses Virtuoso's internal sequence function to generate unique IDs on resources from api_key mapped to source
    # sql:sequence_next("GRAPH_IDENTIFIER") => returns next sequence from GRAPH_IDENTIFIER
    # sql:sequence_set("GRAPH_IDENTIFIER", new_sequence_number, ignoreiflowerthancurrent_boolean) => sets sequence number
    # get unique sequential id by CONSTRUCTing an id based on source URI
    # defaults to "review" if no resource name given
    # nb: to reset count use sequence_set instead, with a CONSTRUCT iri f.ex. like this:
    # `iri(bif:CONCAT("http://data.deichman.no/deichman/reviews/id_", str(bif:sequence_set ('#{GRAPH_IDENTIFIER}', 0, 0)) ) )`
    if source
      # convert to string if RDF::URI
      source.is_a?(RDF::URI) ? source = source.to_s : source
      # parts to compose URI base for resource
      parts = []
      parts << "'#{BASE_URI}'"
      parts << "bif:REPLACE(str(?source), 'http://data.deichman.no/source/', '/')" if resource == "review"
      parts << "'/#{resource}'"
      parts << "'/id_'"
      
      # choose sequence origin, either from review source or from resource
      resource == "review" ? parts << "str(bif:sequence_next ('#{source}'))" : parts << "str(bif:sequence_next ('#{resource}'))"
      
      # CONSTRUCT query  
      query = "CONSTRUCT { `iri( bif:CONCAT( "
      query << parts.join(', ').to_s
      query << " ) )` a <#{RDF::DEICHMAN.DummyClass}> } "
      query << "WHERE { <#{source}> a <#{RDF::FOAF.Document}> ; <#{RDF::FOAF.name}> ?name . ?source a <#{RDF::FOAF.Document}> ; <#{RDF::FOAF.name}> ?name }"
      query << " ORDER BY(?source) LIMIT 1"
      puts "constructing #{resource} id: #{query}" if ENV['RACK_ENV'] == 'development'
      
      solutions = REPO.construct(query)
      
      return nil if solutions.empty?
      puts "constructed #{resource} id: #{solutions.first[:s]}" if ENV['RACK_ENV'] == 'development'
      resource_id = solutions.first[:s]
    end
  end
  
  def get_last_id(source, resource = "review")
    if source
      # convert to string if RDF::URI
      source.is_a?(RDF::URI) ? source = source.to_s : source
      # parts to compose URI base for resource
      parts = []
      parts << "'#{BASE_URI}'"
      parts << "bif:REPLACE(str(?source), 'http://data.deichman.no/source/', '/')" if resource == "review"
      parts << "'/#{resource}'"
      parts << "'/id_'"
      
      # choose sequence origin, either from review source or from resource
      resource == "review" ? parts << "str(bif:sequence_set ('#{source}', 0, 1))" : parts << "str(bif:sequence_set ('#{resource}, 0, 1'))"
      
      # CONSTRUCT query  
      query = "CONSTRUCT { `iri( bif:CONCAT( "
      query << parts.join(', ').to_s
      query << " ) )` a <#{RDF::DEICHMAN.DummyClass}> } "
      query << "WHERE { <#{source}> a <#{RDF::FOAF.Document}> ; <#{RDF::FOAF.name}> ?name . ?source a <#{RDF::FOAF.Document}> ; <#{RDF::FOAF.name}> ?name }"
      query << " ORDER BY(?source) LIMIT 1"
      puts "constructed #{resource} id: #{query}" if ENV['RACK_ENV'] == 'development'
      
      solutions = REPO.construct(query)
      
      return nil if solutions.empty?
      puts "constructed #{resource} id: #{solutions.first[:s]}" if ENV['RACK_ENV'] == 'development'
      resource_id = solutions.first[:s]
    end
  end
  
  def create(params)
    return nil unless params[:name]
    name = params[:name].urlize
    # check if uri is unique
    uri      = RDF::URI("http://data.deichman.no/source/#{name}")
    return "source must be unique" if self.all.detect {|source| source.uri.to_s == uri.to_s }
    
    self.uri      = uri
    self.name     = RDF::Literal(params[:name])
    self.api_key  = ::SecureRandom.uuid
    self.homepage = RDF::URI(params[:homepage]) unless params[:homepage].to_s.strip.length == 0
    self
  end
  
  def update(params={})
    return nil unless self.uri
    self.name     = RDF::Literal(params[:name]) if params[:name]
    self.homepage = RDF::URI(params[:homepage]) unless params[:homepage].to_s.strip.length == 0
    
    # Delete first
    deletequery = QUERY.delete([self.uri, :p, :o]).graph(APIGRAPH)
    deletequery.where([self.uri, :p, :o],[self.uri, RDF.type, RDF::FOAF.Document])
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    save
    self
  end

  def save
    # create Source (foaf:Document)
    insert_statements = []
    insert_statements << RDF::Statement.new(self.uri, RDF.type, RDF::FOAF.Document)
    insert_statements << RDF::Statement.new(self.uri, RDF::FOAF.name, self.name)
    insert_statements << RDF::Statement.new(self.uri, RDF::DEICHMAN.apikey, self.api_key)
    insert_statements << RDF::Statement.new(self.uri, RDF::FOAF.homepage, self.homepage) unless self.homepage.nil?
    
    query = QUERY.insert_data(insert_statements).graph(APIGRAPH)
    puts "create source query: #{query}" if ENV['RACK_ENV'] == 'development'
    result = REPO.insert_data(query)
    return nil if result.empty?
    puts "create source result: #{result}" if ENV['RACK_ENV'] == 'development'
    self
  end

  def delete
    # do nothing if source is not found
    return nil unless self.uri
    deletequery = QUERY.delete([self.uri, :p, :o]).graph(APIGRAPH)
    deletequery.where([self.uri, :p, :o],[self.uri, RDF.type, RDF::FOAF.Document])
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    return result
  end
      
end
