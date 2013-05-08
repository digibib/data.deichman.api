#encoding: utf-8
Account = Struct.new(:uri, :accountName, :password, :status, :accountServiceHomepage, :lastActivity, :myLists)

# main class for account lookup and create/update/delete
class Account

  # MyList is in ./lib/mylist.rb
  def initialize
    self.myLists = []
  end
  
  def all
    query = QUERY.select(:uri, :accountName, :status, :accountServiceHomepage, :lastActivity, :mylist).from(APIGRAPH)
    query.where(
      [:uri, RDF.type, RDF::SIOC.UserAccount],
      [:uri, RDF::FOAF.accountName, :accountName],
      [:uri, RDF::FOAF.accountServiceHomepage, :accountServiceHomepage])
    query.optional([:uri, RDF::ACC.lastActivity, :lastActivity])
    query.optional([:uri, RDF::ACC.status, :status])
    query.optional([:uri, RDF::DEICHMAN.mylist, :myList])
    puts query
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty? # not found!
    puts solutions.inspect if ENV['RACK_ENV'] == 'development'
    accounts = cluster(solutions)
  end
  
  def find(params)
    return nil unless params[:uri] || params[:accountName]
    selects = [:uri, :accountName, :status, :password, :accountServiceHomepage, :myList]
    api = Hashie::Mash.new(:uri => :uri, :accountName => :accountName)
    params[:uri] = RDF::URI(params[:uri]) if params[:uri]
    api.merge!(params)
    # remove variable from selects array if variable given as param
    selects.delete(:uri) if params[:uri]
    selects.delete(:accountName) if params[:accountName]
    query = QUERY.select(*selects).from(APIGRAPH)
    query.where(
      [api[:uri], RDF.type, RDF::SIOC.UserAccount],    
      [api[:uri], RDF::FOAF.accountName, api[:accountName]],
      [api[:uri], RDF::FOAF.accountServiceHomepage, :accountServiceHomepage])
    # optionals
    query.optional([api[:uri], RDF::ACC.status, :status])
    query.optional([api[:uri], RDF::ACC.lastActivity, :lastActivity])
    query.optional([api[:uri], RDF::ACC.password, :password])
    query.optional([api[:uri], RDF::DEICHMAN.mylist, :myList])

    puts "#{query.pp}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty? # not found!
    # need to append uri to solution
    solutions.each{|s| s.merge!(RDF::Query::Solution.new(:uri => params[:uri]))} if params[:uri]
    solutions.each{|s| s.merge!(RDF::Query::Solution.new(:accountName => params[:accountName]))} if params[:accountName]
    puts solutions.inspect if ENV['RACK_ENV'] == 'development'
    # populate Account Struct    
    account = cluster(solutions).first
  end
  
  # clusters solutions based on uri
  def cluster(solutions)
    accounts = []
    distinct_accounts = Marshal.load(Marshal.dump(solutions)).select(:uri).distinct
    # loop each distinct account and iterate matching solutions into a new array
    distinct_accounts.each do |da|
      # make sure distinct filter is run on Marshal clone of solutions
      cluster = Marshal.load(Marshal.dump(solutions)).filter {|solution| solution.uri == da.uri }
      accounts << populate_account(cluster)
    end 
    accounts
  end
  
  # populates Account struct based on cluster
  def populate_account(cluster)
    # first solution creates Account, the rest appends info
    account = Account.new
    account.uri = cluster.first[:uri] 
    account.accountName = cluster.first[:accountName]
    account.password = cluster.first[:password]
    account.accountServiceHomepage = cluster.first[:accountServiceHomepage]
    account.status = cluster.first[:status]
    account.lastActivity = cluster.first[:lastActivity]
    # then the clustered items
    cluster.each { |s| account.myLists << s[:myList] if s[:myList]}
    #list.items.reverse! # hack to simulate returned items in ordred sequence
    account
  end
  
  def authenticate(password)
    self.password == password
  end
  
  def create(params)
    return nil unless params[:accountName]
    # find source
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source

    self.uri = source.autoincrement_resource(source.uri.to_s, resource = "account")
    return nil unless self.uri # break out if unable to generate unique ID
    
    self.accountName = "#{params[:accountName]}"
    self.accountServiceHomepage = source.uri
    self.password = "#{self.accountName.split('@').first}123"
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
    deletequery = QUERY.delete([self.uri, :p, :o]).graph(APIGRAPH)
    deletequery.where([self.uri, :p, :o],[self.uri, RDF.type, RDF::SIOC.UserAccount])
    #puts deletequery
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    
    # Then update
    params.delete(:uri) # don't update uri!
    self.members.each {|name| self[name] = params[name] unless params[name].nil? }
    self.status = RDF::ACC.ActivationNeeded if inactivate
    self.status = nil if activate
    save # save changes to RDF store
    self    
  end
  
  def save
    insert_statements = []
    # create Account (sioc:UserAccount) with dummy password and status: ActivationNeeded
    insert_statements << RDF::Statement.new(self.uri, RDF.type, RDF::SIOC.UserAccount)
    insert_statements << RDF::Statement.new(self.uri, RDF::FOAF.accountName, self.accountName)
    insert_statements << RDF::Statement.new(self.uri, RDF::ACC.password, self.password)
    insert_statements << RDF::Statement.new(self.uri, RDF::FOAF.accountServiceHomepage, self.accountServiceHomepage)
    # optionals
    insert_statements << RDF::Statement.new(self.uri, RDF::ACC.status, self.status) unless self.status.nil?
    insert_statements << RDF::Statement.new(self.uri, RDF::ACC.lastActivity, RDF::Literal(Time.now.xmlschema, :datatype => RDF::XSD.dateTime))
    self.myLists.each { |item| insert_statements << RDF::Statement.new(self.uri, RDF::DEICHMAN.mylist, RDF::URI("#{item}")) }
    query = QUERY.insert_data(insert_statements).graph(APIGRAPH)
    puts query
    puts "create account query: #{query}" if ENV['RACK_ENV'] == 'development'
    result = REPO.insert_data(query)
    return nil if result.empty?
    puts "create account result: #{result}" if ENV['RACK_ENV'] == 'development'
    self
  end
  
  def delete(params)
    # do nothing if account not found
    return nil unless self.uri
    # check api_key
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source    
    
    # delete both reviewer and useraccount
    deletequery = QUERY.delete([self.uri, :p, :o]).graph(APIGRAPH)
    deletequery.where([self.uri, :p, :o],[self.uri, RDF.type, RDF::SIOC.UserAccount])
    puts deletequery
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    return result
  end
end
