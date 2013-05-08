#encoding: utf-8
Author  = Struct.new(:uri, :name)
Edition = Struct.new(:uri, :title, :lang, :cover_url)
Work = Struct.new(:uri, :originalTitle, :prefTitle, :isbns, :editions, :authors, :cover_url, :reviews)

class Work

  def initialize
    self.authors   = []
    self.editions  = []
    self.isbns     = []
    self.reviews   = []
  end

  # Main Work lookup
  # params: uri, title, author, author's URI, isbn
  def find(params)
    return nil unless params[:uri] || params[:title] || params[:isbn] || params[:author] || params[:author_name]
    selects = [:uri, :originalTitle, :title, :lang, :edition, :isbn, :author, :author_name, :cover_url]
    api = Hashie::Mash.new(:uri => :uri, :name => :name, :isbn => :isbn, :author => :author, :author_name => :author_name, :title => :title)
    # handle params
    params[:uri] = RDF::URI(params[:uri]) if params[:uri]
    params[:author] = RDF::URI(params[:author]) if params[:author]
    params[:isbn] = String.new.sanitize_isbn("#{params[:isbn]}") if params[:isbn]
    api.merge!(params)
    selects.delete(:isbn) if api[:isbn] == :isbn
    selects.delete(:uri)  if api[:uri]  == :isbn
    
    # disabled freetext author/title search
    # do we have freetext searches on author/title?
    #author_search   = params[:author_name] ? params[:author_name].gsub(/[[:punct:]]/, '').split(" ") : nil
    #title_search    = params[:title] ? params[:title].gsub(/[[:punct:]]/, '').split(" ") : nil
    
    query = QUERY.select(*selects).from(BOOKGRAPH)
    query.group_digest(:isbn, ', ', 1000, 1) if api[:isbn] == :isbn

    # uri
    api[:uri].is_a?(Symbol) ?
      query.where([api[:uri], RDF.type, RDF::FABIO.Work]) :
      query.where([api[:uri], RDF.type, RDF::FABIO.Work],[:uri, RDF.type, RDF::FABIO.Work])

    # author, also include :author_name variable if queried by api for lookup
    api[:author_name].is_a?(Symbol) ?
      query.where([api[:uri], RDF::DC.creator, api[:author]], [api[:author], RDF::FOAF.name, api[:author_name]]) :
      query.where([api[:uri], RDF::DC.creator, api[:author]], [api[:author], RDF::FOAF.name, api[:author_name]], [api[:author], RDF::FOAF.name, :author_name])
    #query.where([api[:uri], RDF::DC.creator, api[:author]], [api[:author], RDF::FOAF.name, :author_name])
    
    # isbn
    api[:isbn].is_a?(Symbol) ?
      query.where([:uri, RDF::BIBO.isbn, api[:isbn]]) :
      query.where([:uri, RDF::BIBO.isbn, api[:isbn]],[:uri, RDF::BIBO.isbn, :isbn])
   
    query.where(
      [api[:uri], RDF::DC.title, :originalTitle],
      [api[:uri], RDF::BIBO.isbn, api[:isbn]],
      [api[:uri], RDF::FABIO.hasManifestation, :edition],
      [:edition, RDF::DC.language, :lang])
    
    api[:title].is_a?(Symbol) ?
        query.where([:edition, RDF::DC.title, api[:title]]) :
        query.where([:edition, RDF::DC.title, api[:title]], [:edition, RDF::DC.title, :title])
      
    query.optional([:edition, RDF::FOAF.depiction, :cover_url])

    #if author_search
    #  author_search.each do |author|
    #    query.filter("regex(?author_name, \"#{author}\", \"i\")")
    #  end
    #end

    #if title_search
    #  title_search.each do |title|
    #    query.filter("regex(?title, \"#{title}\", \"i\")")
    #  end
    #end

    puts "#{query.pp}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty? # not found!
    #puts solutions.inspect if ENV['RACK_ENV'] == 'development'
    
    works = cluster(solutions, params)
      #work.cover_url = work.cover_url.uniq
      #work.editions  = work.editions.uniq
      #work.isbns     = work.isbns.uniq
      #work.fetch_reviews if params[:reviews]
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
    work.isbns     = (cluster.first[:isbn] ? cluster.first[:isbn].to_s.split(', ') : [params[:isbn]])
    cluster.each do |s|
      work.authors   << Author.new(s[:author], s[:author_name]) unless work.authors.find {|a| a[:uri] == s[:author] }
      work.editions  << Edition.new(s[:edition], s[:title], s[:lang], s[:cover_url]) unless work.editions.find {|a| a[:uri] == s[:edition] }
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
