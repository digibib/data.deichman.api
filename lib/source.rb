#encoding: utf-8
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
      sources << s.to_hash.to_struct("Source")
    end
    sources
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
      puts "constructed #{resource} id: #{query}" if ENV['RACK_ENV'] == 'development'
      
      solutions = REPO.construct(query)
      
      return nil if solutions.empty?
      puts "constructed #{resource} id: #{solutions.first[:s]}" if ENV['RACK_ENV'] == 'development'
      resource_id = solutions.first[:s]
    end
  end
end
