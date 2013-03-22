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
  # params: uri, title, author, isbn
  def find(params)
    return nil unless params[:uri] || params[:title] || params[:isbn] || params[:author] || params[:author_id]
    selects = [:uri, :originalTitle, :title, :lang, :edition, :isbn, :author, :author_id, :cover_url]
    api = Hashie::Mash.new(:uri => :uri, :name => :name, :isbn => :isbn, :author => :author, :author_id => :author_id, :title => :title)
    params[:uri] = RDF::URI(params[:uri]) if params[:uri]
    params[:author_id] = RDF::URI(params[:author_id]) if params[:author_id]
    api.merge!(params)
    selects.delete(:isbn) if api[:isbn] == :isbn
    
    query = QUERY.select(*selects).from(BOOKGRAPH)
    query.group_digest(:isbn, ', ', 1000, 1) if api[:isbn] == :isbn

    # uri
    api[:uri].is_a?(Symbol) ?
      query.where([api[:uri], RDF.type, RDF::FABIO.Work]) :
      query.where([api[:uri], RDF.type, RDF::FABIO.Work],[:uri, RDF.type, RDF::FABIO.Work])

    # author id
    api[:author_id].is_a?(Symbol) ?
      query.where([api[:uri], RDF::DC.creator, api[:author_id]],[api[:author_id], RDF::FOAF.name, api[:author]]) :
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
    
    puts "#{query.pp}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty? # not found!
    puts solutions.inspect if ENV['RACK_ENV'] == 'development'
    
    if params[:cluster]
      works = cluster(solutions)
      #work.cover_url = work.cover_url.uniq
      #work.editions  = work.editions.uniq
      #work.isbns     = work.isbns.uniq
      #work.fetch_reviews if params[:reviews]
    else
      works = []
      solutions.each do |s| 
        work = s.to_hash.to_struct("Work")
        work.isbns = (s[:isbn] ? s[:isbn].to_s.split(', ') : [params[:isbn]])
        #work.originalTitle = s[:originalTitle]
        
        work.fetch_reviews if params[:reviews]
        works << work
      end
    end
    works = cluster(solutions, params)
  end
  
  # This method populates works and authors on works with clustering
  # params: 
  #   :cluster => (Bool) Cluster under distinct works
  #   :reviews => (Bool) Include reviews
  def cluster(solutions, params={:cluster => true, :reviews => true})
    collection = []
    # make a clone of distinct works first
    distinct_works = Marshal.load(Marshal.dump(solutions)).select(:uri).distinct
    # loop each distinct work and iterate matching solutions into a new Work
    distinct_works.each do |ds|
      # make sure distinct filter is run on Marshal clone of solutions
      sorted = Marshal.load(Marshal.dump(solutions)).filter {|solution| solution.uri == ds.uri }
      # first solution creates Work, the rest appends info
      work = Work.new
      work.uri       =  sorted.first[:uri] 
      work.originalTitle = sorted.first[:originalTitle]
      work.cover_url = sorted.first[:cover_url] if sorted.first[:cover_url]
      work.isbns     = (sorted.first[:isbn] ? sorted.first[:isbn].to_s.split(', ') : [params[:isbn]])
      sorted.each do |s|
        work.authors   << Author.new(s[:author_id], s[:author]) unless work.authors.find {|a| a[:uri] == s[:author_id] }
        work.editions  << Edition.new(s[:edition], s[:title], s[:cover_url]) unless work.editions.find {|a| a[:uri] == s[:edition] }
        work.prefTitle  = s[:title] if s[:lang] == RDF::URI("http://lexvo.org/id/iso639-3/nob") || s[:lang] == RDF::URI("http://lexvo.org/id/iso639-3/nno")
      end
      work.fetch_reviews if params[:reviews]
      collection << work
    end
    collection
  end
  
  # not used
  def to_self(work)
    self.members.each {|name| self[name] = work[name] } 
  end
  
  def fetch_reviews
    self.reviews = Review.new.find_by_work(self.uri)
  end

end
