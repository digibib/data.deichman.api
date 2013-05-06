#encoding: utf-8
MyList  = Struct.new(:uri, :label, :items)

# main class for myList lookup and create/update/delete
class MyList

  def initialize
    self.items = []
  end
  
  def all
    query = QUERY.select(:uri, :label, :item).from(APIGRAPH)
    query.where(
      [:uri, RDF.type, RDF.Seq],
      [:uri, RDF::RDFS.label, :label])
    query.optional([:uri, RDF.li, :item])
    puts query
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty? # not found!
    
    puts solutions.inspect if ENV['RACK_ENV'] == 'development'
    mylists = cluster(solutions)
  end
  
  # find list by uri
  def find(params)
    return nil unless params[:uri]
    uri = RDF::URI(params[:uri])    
    query = QUERY.select(:uri, :label, :item).from(APIGRAPH)
    query.where(
      [uri, RDF.type, RDF.Seq],
      [uri, RDF::RDFS.label, :label])
    query.optional([uri, RDF.li, :item])

    puts "#{query.pp}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty? # not found!
    # need to append uri to solution
    solutions = solutions.first.merge(RDF::Query::Solution.new(:uri => uri))
    puts solutions
    puts solutions.inspect if ENV['RACK_ENV'] == 'development'
    mylists = cluster(solutions)
  end
  
  def find_by_uri(params)
    return nil unless params[:uri]
    self.all.detect {|mylist| mylist.uri == params[:uri] }
  end
  
  def cluster(solutions)
    lists = []
    distinct_lists = Marshal.load(Marshal.dump(solutions)).select(:uri).distinct
    # loop each distinct work and iterate matching solutions into a new Work
    distinct_lists.each do |dl|
      # make sure distinct filter is run on Marshal clone of solutions
      cluster = Marshal.load(Marshal.dump(solutions)).filter {|solution| solution.uri == dl.uri }
      lists << populate_list(cluster)
    end 
    lists
  end
  
  # populates MyList struct based on cluster, optionally with reviews
  def populate_list(cluster)
    # first solution creates MyList, the rest appends info
    list = MyList.new
    list.uri   = cluster.first[:uri] 
    list.label = cluster.first[:label]
    cluster.each { |s| list.items << s[:item] }
    puts list.items
    list.items.reverse! # hack to simulate returned items in ordred sequence
    list
  end
  
  
  def create(params)
    # find source
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source

    self.uri = source.autoincrement_resource(source.uri.to_s, resource = "mylist")
    return nil unless self.uri # break out if unable to generate unique ID
    
    self.label = "#{params[:label]}"
    self.items = Array(params[:items])
    self
  end

  def update(params)
    # find source
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source
    
    # Delete first
    deletequery = QUERY.delete([self.uri, :p, :o]).graph(APIGRAPH)
    deletequery.where([self.uri, :p, :o], [self.uri, RDF.type, RDF.Seq])
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
    # create MyList (RDF:Seq) in ordered sequence 
    insert_statements << RDF::Statement.new(self.uri, RDF.type, RDF.Seq)
    insert_statements << RDF::Statement.new(self.uri, RDF::RDFS.label, self.label)
    self.items.each do |item|
      insert_statements << RDF::Statement.new(self.uri, RDF.li, item)
    end
    query = QUERY.insert_data(insert_statements).graph(APIGRAPH)
    puts query
    puts "create mylist query: #{query}" if ENV['RACK_ENV'] == 'development'
    result = REPO.insert_data(query)
    return nil if result.empty?
    puts "create mylist result: #{result}" if ENV['RACK_ENV'] == 'development'
    self
  end
  
  def delete(params)
    # do nothing if mylist not found
    return nil unless self.uri
    # check api_key
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source    
    
    # delete mylist
    deletequery = QUERY.delete([self.uri, :p, :o],[:userAccount, :p2, self.uri]).graph(APIGRAPH)
    deletequery.where([self.uri, :p, :o],[:userAccount, :p2, self.uri])
    puts deletequery
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    return result
  end
end
