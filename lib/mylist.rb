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
    lists = cluster(solutions)
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
    solutions.each{|s| s.merge!(RDF::Query::Solution.new(:uri => uri))}
    puts solutions.inspect if ENV['RACK_ENV'] == 'development'
    list = cluster(solutions).first
  end
  
  # not used! uses find method with separate query p.t.
  def find_by_uri(params)
    return nil unless params[:uri]
    self.all.detect {|mylist| mylist.uri == params[:uri] }
  end
  
  # clusters solutions based on uri
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
  
  # populates MyList struct based on cluster
  def populate_list(cluster)
    # first solution creates MyList, the rest appends info
    list = MyList.new
    list.uri   = cluster.first[:uri] 
    list.label = cluster.first[:label]
    list.items = cluster.first[:item]
    #cluster.each { |s| list.items << s[:item] }
    #list.items.reverse! # rdf store needs to write in reversed sequence!
    list.items = list.items.to_s.split(',') if list.items
    list
  end
  
  # creates a new MyList
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
    # RDF Lists are not trivial, puts them into a long csv string instead
    # self.items.each { |item| insert_statements << RDF::Statement.new(self.uri, RDF.li, RDF::URI("#{item}")) }
    insert_statements << RDF::Statement.new(self.uri, RDF.li, RDF::Literal(self.items.join(',')) )
    query = QUERY.insert_data(insert_statements).graph(APIGRAPH)
    #puts query
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
    deletequery.where([self.uri, :p, :o],[self.uri, RDF.type, RDF.Seq], [:userAccount, :p2, self.uri])
    puts deletequery
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    return result
  end
end
