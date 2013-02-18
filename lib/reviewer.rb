Reviewer = Struct.new(:uri, :name, :workplaceHomepage, :userAccount, :accountName, :password, :email, :status, :accountServiceHomepage, :workplace, :workplace_id)
class Reviewer
  def all
    query = QUERY.select(:uri, :name, :userAccount, :accountName, :email, :status, 
                        :accountServiceHomepage, :workplace, :workplace_id).from(APIGRAPH)
    query.where(
      [:uri, RDF.type, RDF::FOAF.Person],
    # reviewer by foaf name
      [:uri, RDF::FOAF.name, :name],
    # reviewer by accountname
      [:uri, RDF::FOAF.account, :userAccount],
      [:userAccount, RDF::FOAF.accountName, :accountName],
      [:userAccount, RDF::FOAF.accountServiceHomepage, :accountServiceHomepage])
    # reviewer workplace
    query.optional(
      [:uri, RDF::ORG.memberOf, :workplace_id],
      [:workplace_id, RDF::SKOS.prefLabel, :workplace])
    query.optional([:userAccount, RDF::ACC.status, :status])
    query.optional([:userAccount, RDF::SIOC.email, :email])    
    query.optional([:userAccount, RDF::ACC.password, :password])    
    query.optional([:userAccount, RDF::FOAF.workplaceHomepage, :workplaceHomepage])
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty? # not found!
    #puts solutions.inspect if ENV['RACK_ENV'] == 'development'
    reviewers = []
    solutions.each do |s|
      reviewer = s.to_hash.to_struct("Reviewer")
      reviewer.password = nil
      reviewers << reviewer
    end
    reviewers
  end
  
  def find(params)
    return nil unless params[:uri] || params[:name]
    selects = [:uri, :name, :workplaceHomepage, :userAccount, :accountName, :email, :status, :password,  
                        :accountServiceHomepage, :workplace, :workplace_id]
    api = Hashie::Mash.new(:uri => :uri, :name => :name, :isbn => :isbn, :author => :author, :author_id => :author_id, :title => :title)
    params[:uri] = RDF::URI(params[:uri]) if params[:uri]
    api.merge!(params)
    # remove variable from selects array if variable given as param
    selects.delete_if {|s| params[s]}
    
    query = QUERY.select(*selects).from(APIGRAPH)
    query.where([api[:uri], RDF.type, RDF::FOAF.Person],
    # reviewer by foaf name
      [api[:uri], RDF::FOAF.name, :name],
    # reviewer by accountname
      [api[:uri], RDF::FOAF.account, :userAccount],
      [:userAccount, RDF::FOAF.accountName, :accountName],
      [:userAccount, RDF::FOAF.accountServiceHomepage, :accountServiceHomepage])
    # reviewer workplace
    query.optional(
      [api[:uri], RDF::ORG.memberOf, :workplace_id],
      [:workplace_id, RDF::SKOS.prefLabel, :workplace])    
    # status
    query.optional([:userAccount, RDF::ACC.status, :status])
    query.optional([:userAccount, RDF::SIOC.email, :email])    
    query.optional([:userAccount, RDF::ACC.password, :password])
    query.optional([api[:uri], RDF::FOAF.workplaceHomepage, :workplaceHomepage])
    query.filter('regex(?name, "' + api[:name] + '", "i")') if params[:name]
    query.filter('regex(?workplace, "' + api[:workplace] + '", "i")') if params[:workplace]  
    #puts query
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty? # not found!
    puts solutions.inspect if ENV['RACK_ENV'] == 'development'
    self.uri  = params[:uri] if params[:uri] 
    self.name = params[:name] if params[:name]
    # populate Review Struct    
    self.members.each {|name| self[name] = solutions.first[name] unless solutions.first[name].nil? }  
    self
  end
  
  def authenticate(password)
    self.password == password
  end
  
  def create(params)
    # find source
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source
    
    # create a new reviewer id, Reviewer and Account
    self.uri = source.autoincrement_resource(source.uri.to_s, resource = "reviewer")
    return nil unless self.uri # break out if unable to generate unique ID
    
    self.userAccount = source.autoincrement_resource(source.uri.to_s, resource = "account")
    return nil unless self.userAccount # break out if unable to generate unique ID
    
    # add link to workplace if found
    if params[:workplace]
      workplace = Workplace.new.find(params)
      if workplace
        self.workplace_id = workplace.uri
        self.workplace    = workplace.prefLabel.to_s
      end
    end
    self.workplaceHomepage = RDF::URI("#{params[:workplaceHomepage]}") if params[:workplaceHomepage]
    self.accountName = "#{params[:name].urlize}"
    self.accountServiceHomepage = source.name
    self.name     = "#{params[:name]}"
    self.password = "#{self.accountName.to_s}123"
    self.email    = "#{params[:email]}"
    self.status   = RDF::ACC.ActivationNeeded
    self
  end

  def update(params)
    # find source
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source

    # make activate or inactivate switches
    inactivate = true if !self.status && params[:active] == false
    activate   = true if self.status && params[:active] == true
    
    # Delete first
    deletequery = QUERY.delete([self.uri, :p, :o],[self.userAccount, :p2, :o2]).graph(APIGRAPH)
    deletequery.where([self.uri, :p, :o],[self.uri, RDF.type, RDF::FOAF.Person],
                      [self.userAccount, :p2, :o2],[self.userAccount, RDF.type, RDF::SIOC.UserAccount])
    #puts deletequery
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    
    # Then update
    # update reviewer with new params    
    self.members.each {|name| self[name] = params[name] unless params[name].nil? }
    self.status = RDF::ACC.ActivationNeeded if inactivate
    self.status = nil if activate
    save # save changes to RDF store
    self    
  end
  
  def save
    insert_statements = []
    # create Reviewer (foaf:Person)
    insert_statements << RDF::Statement.new(self.uri, RDF.type, RDF::FOAF.Person)
    insert_statements << RDF::Statement.new(self.uri, RDF::FOAF.name, self.name)
    insert_statements << RDF::Statement.new(self.uri, RDF::FOAF.account, self.userAccount)
    # optional
    insert_statements << RDF::Statement.new(self.uri, RDF::ORG.memberOf, self.workplace_id) unless self.workplace_id.nil?
    insert_statements << RDF::Statement.new(self.uri, RDF::FOAF.workplaceHomepage, self.workplaceHomepage) unless self.workplaceHomepage.nil?
    # create Account (sioc:UserAccount) with dummy password and status: ActivationNeeded
    insert_statements << RDF::Statement.new(self.userAccount, RDF.type, RDF::SIOC.UserAccount)
    insert_statements << RDF::Statement.new(self.userAccount, RDF::FOAF.accountName, self.accountName)
    insert_statements << RDF::Statement.new(self.userAccount, RDF::ACC.password, self.password)
    insert_statements << RDF::Statement.new(self.userAccount, RDF::FOAF.accountServiceHomepage, self.accountServiceHomepage)
    # optionals
    insert_statements << RDF::Statement.new(self.userAccount, RDF::SIOC.email, self.email) unless self.email.nil?
    insert_statements << RDF::Statement.new(self.userAccount, RDF::ACC.status, self.status) unless self.status.nil?
    insert_statements << RDF::Statement.new(self.userAccount, RDF::ACC.lastActivity, RDF::Literal(Time.now.xmlschema, :datatype => RDF::XSD.dateTime))
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
    deletequery = QUERY.delete([self.uri, :p, :o],[self.userAccount, :p2, :o2]).graph(APIGRAPH)
    deletequery.where([self.uri, :p, :o],[self.uri, RDF.type, RDF::FOAF.Person],
                      [self.userAccount, :p2, :o2],[self.userAccount, RDF.type, RDF::SIOC.UserAccount])
    puts deletequery
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    return result
  end
end
