#encoding: utf-8
Workplace = Struct.new(:uri, :prefLabel, :homepage)
class Workplace
  def all
    query = QUERY.select(:uri, :prefLabel, :homepage).from(APIGRAPH)
    query.where(
      [:uri, RDF.type, RDF::ORG.Organization],
      [:uri, RDF::SKOS.prefLabel, :prefLabel])
    query.optional([:uri, RDF::FOAF.homepage, :homepage])
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty? # not found!
    #puts solutions.inspect if ENV['RACK_ENV'] == 'development'
    workplaces = []
    solutions.each do |s|
      workplaces << s.to_hash.to_struct("Workplace")
    end
    workplaces
  end
  
  def find(params)
    return nil unless params[:reviewer] || params[:workplace]
    # looks in apigraph for reviewer by either reviewer's foaf:name or reviewer account's foaf:accountName

    query = QUERY.select(:uri, :prefLabel, :homepage).from(APIGRAPH)
    query.where(
      [:uri, RDF.type, RDF::ORG.Organization],
      [:uri, RDF::SKOS.prefLabel, :prefLabel])
    query.optional([:uri, RDF::FOAF.homepage, :homepage])
    query.filter("regex(?prefLabel, \"#{params[:workplace]}\", \"i\") || regex(str(?uri), \"#{params[:workplace]}\", \"i\")") if params[:workplace]
    puts query
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty? # not found!
    puts solutions.inspect if ENV['RACK_ENV'] == 'development'

    # populate Workplace Struct    
    self.members.each {|name| self[name] = solutions.first[name] }  
    self
  end
  
  def create(params)
    # find source
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source
    
    # create a new workplace id, with homepage and prefLabel
    self.uri = RDF::DEICHMAN.workplace + "/#{params[:workplace].urlize}"
    return nil unless self.uri # break out if unable to generate unique ID
    
    self.prefLabel = "#{params[:workplace]}"
    self.homepage  = RDF::URI("#{params[:homepage]}") if params[:homepage]
    self
  end

  def update(params)
    # find source
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source

    # Delete first
    deletequery = QUERY.delete([self.uri, :p, :o]).graph(APIGRAPH)
    deletequery.where([self.uri, :p, :o],[self.uri, RDF.type, RDF::ORG.Organization])
    puts deletequery
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    puts result
    # then update from new params
    params[:prefLabel] = params[:workplace] 
    self.members.each {|name| self[name] = params[name] unless params[name].nil? }
    puts self
    save # save changes to RDF store
    self    
  end
  
  def save
    insert_statements = []
    # create Workplace (org:Organization)
    insert_statements << RDF::Statement.new(self.uri, RDF.type, RDF::ORG.Organization)
    insert_statements << RDF::Statement.new(self.uri, RDF.type, RDF::FOAF.Organization)
    insert_statements << RDF::Statement.new(self.uri, RDF::SKOS.prefLabel, self.prefLabel)
    insert_statements << RDF::Statement.new(self.uri, RDF::FOAF.homepage, self.homepage) unless self.homepage.nil?
    
    query = QUERY.insert_data(insert_statements).graph(APIGRAPH)

    puts "create reviewer query: #{query}" if ENV['RACK_ENV'] == 'development'
    result = REPO.insert_data(query)
    return nil if result.empty?
    puts "create reviewer result: #{result}" if ENV['RACK_ENV'] == 'development'
    self
  end
    
  def delete
    # do nothing if workplace not found
    return nil unless self.uri
    deletequery = QUERY.delete([self.uri, :p, :o]).graph(APIGRAPH)
    deletequery.where([self.uri, :p, :o],[self.uri, RDF.type, RDF::ORG.Organization])
    puts deletequery
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    return result
  end
end
