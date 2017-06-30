#encoding: utf-8
Author  = Struct.new(:uri, :name)
Edition = Struct.new(:uri, :title, :lang, :cover_url, :altDepictedBy, :isbn)
Work = Struct.new(:uri, :originalTitle, :prefTitle, :editions, :authors, :cover_url, :reviews)

class Work

  def initialize
    self.authors   = []
    self.editions  = []
    #self.isbns     = []
    self.reviews   = []
  end

  # Main Work lookup
  # params: uri, title, author, author's URI, isbn
  def find(params)
    return nil unless params[:uri] || params[:title] || params[:isbn] || params[:author] || params[:author_name]
    selects = [:uri, :originalTitle, :title, :lang, :edition, :isbn, :author, :author_name, :cover_url]
    api = HashWithIndifferentAccess.new(:uri => :uri, :name => :name, :isbn => :isbn, :author => :author, :author_name => :author_name, :title => :title)
    # handle params
    params[:uri]    = RDF::URI(params[:uri]) if params[:uri]
    params[:author] = RDF::URI(params[:author]) if params[:author]
    params[:isbn]   = String.sanitize_isbn("#{params[:isbn]}") if params[:isbn]
    api.merge!(params)
    selects.delete(:isbn)   if params[:isbn]
    selects.delete(:uri)    if params[:uri]
    selects.delete(:title)  if params[:title]
    selects.delete(:author) if params[:author]

    query = QUERY.select(*selects).from(BOOKGRAPH)
    query.sample(:altDepictedBy)
    # compose query based on api params
    if params[:author]
      query.where(
        [api[:uri], RDF::DC.creator, api[:author]], [api[:author], RDF::FOAF.name, api[:author_name]],
        [api[:uri], RDF.type, RDF::FABIO.Work],
        [api[:uri], RDF::DC.title, :originalTitle],
        [api[:uri], RDF::FABIO.hasManifestation, :edition],
        [:edition, RDF::DC.language, :lang],
        [:edition, RDF::DC.title, api[:title]])
      query.optional(
        [:edition, RDF::BIBO.isbn, api[:isbn]])
    elsif params[:isbn]
      query.where(
        [:edition, RDF::BIBO.isbn, api[:isbn]],
        [:edition, RDF::DC.language, :lang],
        [:edition, RDF::DC.title, api[:title]],
        [api[:uri], RDF::FABIO.hasManifestation, :edition],
        [api[:uri], RDF.type, RDF::FABIO.Work],
        [api[:uri], RDF::DC.title, :originalTitle])
      query.optional(
        [api[:uri], RDF::DC.creator, api[:author]],
        [api[:author], RDF::FOAF.name, api[:author_name]])
    else
      query.where(
        [api[:uri], RDF.type, RDF::FABIO.Work],
        [api[:uri], RDF::DC.title, :originalTitle],
        [api[:uri], RDF::FABIO.hasManifestation, :edition],
        [:edition, RDF::DC.language, :lang],
        [:edition, RDF::DC.title, api[:title]])
      query.optional(
        [api[:uri], RDF::DC.creator, api[:author]],
        [api[:author], RDF::FOAF.name, api[:author_name]])
      query.optional([:edition, RDF::BIBO.isbn, api[:isbn]])
    end
    query.optional([:edition, RDF::FOAF.depiction, :cover_url])
    query.optional([:edition, RDF::IFACE.altDepictedBy, :altDepictedBy])

    puts "#{query.pp}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)

    return nil if solutions.empty? # not found!
    # append to solution if given as params
    solutions.each{|s| s.merge!(RDF::Query::Solution.new(:uri    => params[:uri]))} if params[:uri]
    solutions.each{|s| s.merge!(RDF::Query::Solution.new(:author => params[:author]))} if params[:author]
    solutions.each{|s| s.merge!(RDF::Query::Solution.new(:isbn   => params[:isbn]))} if params[:isbn]
    solutions.each{|s| s.merge!(RDF::Query::Solution.new(:title  => params[:title]))} if params[:title]

    puts solutions.inspect if ENV['RACK_ENV'] == 'development'

    works = cluster(solutions, params)
  end

  # This method populates works and authors on works with clustering
  # params:
  #   :cluster => (Bool) Cluster under distinct works. Default false
  #   :reviews => (Bool) Include reviews               Default true
  def cluster(solutions, params)
    works = []
      # make a clone of distinct works first
      distinct_works = Marshal.load(Marshal.dump(solutions)).select(:uri).distinct
      # loop each distinct work and iterate matching solutions into a new Work
      distinct_works.each do |ds|
        # make sure distinct filter is run on Marshal clone of solutions
        cluster = Marshal.load(Marshal.dump(solutions)).filter {|solution| solution.uri == ds.uri }
        works << populate_work(cluster, params)
      end
    works
  end

  # populates work struct based on cluster, optionally with reviews
  def populate_work(cluster, params)
    # first solution creates Work, the rest appends info
    work = Work.new
    work.uri       =  cluster.first[:uri]
    work.originalTitle = cluster.first[:originalTitle]
    work.cover_url = cluster.first[:cover_url] if cluster.first[:cover_url]
    #work.isbns     = (cluster.first[:isbn] ? cluster.first[:isbn].to_s.split(', ') : [params[:isbn]])
    cluster.each do |s|
      work.authors   << Author.new(s[:author], s[:author_name]) unless work.authors.find {|a| a[:uri] == s[:author] }
      work.editions  << Edition.new(s[:edition], s[:title], s[:lang], s[:cover_url], s[:altDepictedBy], s[:isbn]) unless work.editions.find {|a| a[:uri] == s[:edition] }
      work.prefTitle  = s[:title] if s[:lang] == RDF::URI("http://lexvo.org/id/iso639-3/nob") || s[:lang] == RDF::URI("http://lexvo.org/id/iso639-3/nno")
    end
    work.reviews = fetch_reviews(work.uri) if params[:reviews] == true
    work
  end

  # not used
  def to_self(work)
    self.members.each {|name| self[name] = work[name] }
  end

  def fetch_reviews(uri)
    Review.new.find(:work => uri, :published => true)
  end

end
