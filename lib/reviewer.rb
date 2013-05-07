#encoding: utf-8
Reviewer = Struct.new(:uri, :name, :workplaceHomepage, :userAccount)

# main class for reviewer lookup and create/update/delete
class Reviewer
  def all
    query = QUERY.select(:uri, :name, :workplaceHomepage, :userAccount).from(APIGRAPH)
    query.where(
      [:uri, RDF.type, RDF::FOAF.Person],
      [:uri, RDF::FOAF.name, :name],
      [:uri, RDF::FOAF.account, :userAccount])
    query.optional([:uri, RDF::FOAF.workplaceHomepage, :workplaceHomepage])
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty? # not found!
    puts solutions.inspect if ENV['RACK_ENV'] == 'development'
    reviewers = []
    solutions.each do |s|
      reviewer = s.to_hash.to_struct("Reviewer")
      reviewers << reviewer
    end
    reviewers
  end
  
  # accept uri or userAccount
  def find(params)
    return nil unless params[:uri] || params[:userAccount]
    selects = [:uri, :name, :workplaceHomepage, :userAccount]
    uri         = params[:uri] ? RDF::URI(params[:uri]) : :uri
    useraccount = params[:userAccount] ? RDF::URI(params[:userAccount]) : :userAccount
    select.delete(:uri) if params[:uri]
    select.delete(:userAccount) if params[:userAccount]
    
    query = QUERY.select(*selects).from(APIGRAPH)
    query.where(
      [uri, RDF.type, RDF::FOAF.Person],
      [uri, RDF::FOAF.name, :name],
      [uri, RDF::FOAF.account, useraccount])
    query.optional([uri, RDF::FOAF.workplaceHomepage, :workplaceHomepage])
    puts "#{query.pp}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty? # not found!
    puts solutions.inspect if ENV['RACK_ENV'] == 'development'
    # populate Review Struct    
    self.members.each {|name| self[name] = solutions.first[name] unless solutions.first[name].nil? } 
    self.uri         = uri if params[:uri]
    self.userAccount = userAccount if params[:userAccount]
    self
  end
  
  def create(params)
    # find source
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source

    # create a new Reviewer
    self.uri = source.autoincrement_resource(source.uri.to_s, resource = "reviewer")
    return nil unless self.uri # break out if unable to generate unique ID
    
    self.workplaceHomepage = RDF::URI("#{params[:workplaceHomepage]}") if params[:workplaceHomepage]
    self.name = "#{params[:name]}"
    self
  end

  def update(params)
    # find source
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source

    # Delete first
    deletequery = QUERY.delete([self.uri, :p, :o]).graph(APIGRAPH)
    deletequery.where([self.uri, :p, :o],[self.uri, RDF.type, RDF::FOAF.Person])
    #puts deletequery
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    
    # Then update
    params.delete(:uri) # don't update uri!
    self.members.each {|name| self[name] = params[name] unless params[name].nil? }
    save # save changes to RDF store
    self    
  end
  
  def save
    insert_statements = []
    # create Reviewer (foaf:Person)
    insert_statements << RDF::Statement.new(self.uri, RDF.type, RDF::FOAF.Person)
    insert_statements << RDF::Statement.new(self.uri, RDF::FOAF.name, self.name)
    insert_statements << RDF::Statement.new(self.uri, RDF::FOAF.account, self.userAccount)
    query = QUERY.insert_data(insert_statements).graph(APIGRAPH)

    puts "create reviewer query: #{query}" if ENV['RACK_ENV'] == 'development'
    result = REPO.insert_data(query)
    return nil if result.empty?
    puts "create reviewer result: #{result}" if ENV['RACK_ENV'] == 'development'
    self
  end
  
  def delete(params)
    # do nothing if reviewer not found
    return nil unless self.uri
    # check api_key
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source    
    
    # delete both reviewer and useraccount
    deletequery = QUERY.delete([self.uri, :p, :o]).graph(APIGRAPH)
    deletequery.where([self.uri, :p, :o],[self.uri, RDF.type, RDF::FOAF.Person])
    puts deletequery
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    return result
  end
end
