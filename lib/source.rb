class Review
  def find_source_by_apikey(api_key)
    # fetch source by api key in protected graph
    # each source needs three statements: 
    # <source> a rdfs:Resource ;
    #          rdfs:label "Label" ;
    #          deichman:apikey "apikey" .    
    query = QUERY.select(:source).from(APIGRAPH)
    query.where(
      [:source, RDF.type, RDF::FOAF.Document], 
      [:source, RDF::FOAF.name, :label],
      [:source, RDF::DEICHMAN.apikey, "#{api_key}"])
    query.limit(1)
    #puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty?
    source = solutions.first[:source]
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
      puts "#{query}" if ENV['RACK_ENV'] == 'development'
      
      solutions = REPO.construct(query)
      
      return nil if solutions.empty?
      resource_id = solutions.first[:s]
    end
  end
end
