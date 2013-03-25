#encoding: utf-8
Author  = Struct.new(:uri, :name)
Edition = Struct.new(:uri, :title, :cover)
Work = Struct.new(:uri, :originalTitle, :prefTitle, :isbns, :editions, :authors, :cover_url, :reviews)

class Work

  def initialize
    self.authors   = []
    self.editions  = []
    self.isbns     = []
    self.reviews   = []
  end
  # under construction
  # params: uri, title, author, author's URI, isbn
  def find(params)
    return nil unless params[:uri] || params[:title] || params[:isbn] || params[:author] || params[:author_id]
    selects = [:uri, :originalTitle, :title, :lang, :edition, :isbn, :author, :author_id, :cover_url]
    api = Hashie::Mash.new(:uri => :uri, :name => :name, :isbn => :isbn, :author => :author, :author_id => :author_id, :title => :title)
    # handle params
    params[:uri] = RDF::URI(params[:uri]) if params[:uri]
    params[:author_id] = RDF::URI(params[:author_id]) if params[:author_id]
    params[:isbn] = String.new.sanitize_isbn("#{params[:isbn]}") if params[:isbn]
    api.merge!(params)
    selects.delete(:isbn) if api[:isbn] == :isbn
    
    # disabled freetext author/title search
    # do we have freetext searches on author/title?
    #author_search   = params[:author] ? params[:author].gsub(/[[:punct:]]/, '').split(" ") : nil
    #title_search    = params[:title] ? params[:title].gsub(/[[:punct:]]/, '').split(" ") : nil
    
    query = QUERY.select(*selects).from(BOOKGRAPH)
    query.group_digest(:isbn, ', ', 1000, 1) if api[:isbn] == :isbn

    # uri
    api[:uri].is_a?(Symbol) ?
      query.where([api[:uri], RDF.type, RDF::FABIO.Work]) :
      query.where([api[:uri], RDF.type, RDF::FABIO.Work],[:uri, RDF.type, RDF::FABIO.Work])

    # author id
    api[:author_id].is_a?(Symbol) ?
      query.where([api[:uri], RDF::DC.creator, api[:author_id]],[api[:author_id], RDF::FOAF.name, :author]) :
      query.where([api[:uri], RDF::DC.creator, api[:author_id]],[api[:author_id], RDF::FOAF.name, api[:author]],[:author_id, RDF::FOAF.name, :author])
    
    # author 
    api[:author].is_a?(Symbol) ?
      query.where([:author_id, RDF::FOAF.name, api[:author]]) :
      query.where([:author_id, RDF::FOAF.name, api[:author]],[:author_id, RDF::FOAF.name, :author])
    # isbn
    api[:isbn].is_a?(Symbol) ?
      query.where([:uri, RDF::BIBO.isbn, api[:isbn]]) :
      query.where([:uri, RDF::BIBO.isbn, api[:isbn]],[:uri, RDF::BIBO.isbn, :isbn])
    query.where(
      [api[:uri], RDF::DC.title, :originalTitle],
      [api[:uri], RDF::BIBO.isbn, api[:isbn]],
      [api[:uri], RDF::FABIO.hasManifestation, :edition],
      [:edition, RDF::DC.title, :title],
      [:edition, RDF::DC.language, :lang]
      )
    query.optional([:edition, RDF::FOAF.depiction, :cover_url])
=begin
  disabled freetext search
    if author_search
      author_search.each do |author|
        query.filter("regex(?author, \"#{author}\", \"i\")")
      end
    end

    if title_search
      title_search.each do |title|
        query.filter("regex(?title, \"#{title}\", \"i\")")
      end
    end
=end    
    puts "#{query.pp}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty? # not found!
    puts solutions.inspect if ENV['RACK_ENV'] == 'development'
    
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
  def cluster(solutions, params={})
    works = []
    #if params[:cluster]
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
  def populate_work(cluster, params={:reviews => true})
    # first solution creates Work, the rest appends info
    work = Work.new
    work.uri       =  cluster.first[:uri] 
    work.originalTitle = cluster.first[:originalTitle]
    work.cover_url = cluster.first[:cover_url] if cluster.first[:cover_url]
    work.isbns     = (cluster.first[:isbn] ? cluster.first[:isbn].to_s.split(', ') : [params[:isbn]])
    cluster.each do |s|
      work.authors   << Author.new(s[:author_id], s[:author]) unless work.authors.find {|a| a[:uri] == s[:author_id] }
      work.editions  << Edition.new(s[:edition], s[:title], s[:cover_url]) unless work.editions.find {|a| a[:uri] == s[:edition] }
      work.prefTitle  = s[:title] if s[:lang] == RDF::URI("http://lexvo.org/id/iso639-3/nob") || s[:lang] == RDF::URI("http://lexvo.org/id/iso639-3/nno")
    end
    work.reviews = fetch_reviews(work.uri) if params[:reviews]
    work
  end
  
  # not used
  def to_self(work)
    self.members.each {|name| self[name] = work[name] } 
  end
  
  def fetch_reviews(uri)
    Review.new.find(:work => uri)
  end

end
