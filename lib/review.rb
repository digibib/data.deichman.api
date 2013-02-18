#encoding: utf-8

Review = Struct.new(:uri, :title, :teaser, :text, :source, :reviewer, :workplace, 
          :audience, :subject, :work_id, :book_id, :created, :issued, :modified, :published)

class Review
  
  # return all reviews, but with limits...
  def all(params={:limit=>10, :offset=>0, :order_by=>"author", :order=>"asc"})
    selects     = [:uri, :work_id, :book_id, :book_title, :created, :issued, :modified, :review_title, :review_abstract, :review_source, :reviewer_name, :accountName, :workplace]
    solutions = review_query(selects, params)
    solutions.empty? ? reviews = nil : reviews = populate_works(solutions, :params => params, :cluster => false)
    reviews
  end
  
  # main method to find reviews, GET /api/review
  # params: uri, isbn, title, author, reviewer, work
  # TODO: published true/false
  def find(params={})
    selects = [:uri, :work_id, :book_id, :book_title, :created, :issued, :modified, :review_title, :review_abstract, :review_source, :reviewer_name, :accountName, :workplace]

    # this clause composes query attributes modified by params from API
    if params.has_key?(:uri)
      # if uri param is Array, iterate URIs and merge solutions into separate works
      if params[:uri].is_a?(Array)
        works = []
        solutions = RDF::Query::Solutions.new
        selects.delete(:uri)
        params[:uri].each do |u|
          begin
            uri = URI::parse(u)
            uri = RDF::URI(uri)
            res = review_query(selects, :uri => uri)
            unless res.empty?
              # need to append uri to solution for later use
              solution = res.first.merge(RDF::Query::Solution.new(:uri => uri))
              # then merge into solutions
              solutions << solution 
            end
          rescue URI::InvalidURIError
            return "Invalid URI"
          end
        end
        solutions.empty? ? works = nil : works = populate_works(solutions, :uri => uri, :cluster => false) 
      else
        begin
          solutions = RDF::Query::Solutions.new
          selects.delete(:uri)
          uri = URI::parse(params[:uri])
          uri = RDF::URI(uri)
          res = review_query(selects, :uri => uri)
          unless res.empty?
            # need to append uri to solution for later use
            solution = res.first.merge(RDF::Query::Solution.new(:uri => uri))
            # then merge into solutions
            solutions << solution 
          end
        rescue URI::InvalidURIError
          return "Invalid URI"
        end
        solutions.empty? ? works = nil : works = populate_works(solutions, :uri => uri, :cluster => true) 
      end
    elsif params.has_key?(:isbn)
      isbn      = String.new.sanitize_isbn("#{params[:isbn]}")
      solutions = review_query(selects, :isbn => isbn)
      solutions.empty? ? works = nil : works = populate_works(solutions, :isbn => isbn, :cluster => true)
    elsif params.has_key?(:work)
      begin 
        selects.delete(:work_id)
        uri = URI::parse(params[:work])
        uri = RDF::URI(uri)
        solutions = review_query(selects, :work => uri)
        solutions.empty? ? works = nil : works = populate_works(solutions, :work => uri, :cluster => true)
      rescue URI::InvalidURIError
        return "Invalid URI"
      end
    elsif params.has_key?(:author_id)
      begin 
        uri = URI::parse(params[:author_id])
        uri = RDF::URI(uri)
        solutions = review_query(selects, :author_id => uri)
        solutions.empty? ? works = nil : works = populate_works(solutions, :author_id => uri, :cluster => true)
      rescue URI::InvalidURIError
        return "Invalid URI"
      end   
    elsif params.has_key?(:reviewer)
      reviewer = Reviewer.new.find(:name => params[:reviewer])
      if reviewer
        solutions = review_query(selects, :reviewer => reviewer.uri)
        solutions.empty? ? works = nil : works = populate_works(solutions, :reviewer => reviewer.uri, :cluster => true)
      else
        return "Invalid Reviewer"
      end
    elsif params.has_key?(:workplace)
      reviewer = Reviewer.new.find(:workplace => params[:workplace])
      if reviewer
        solutions = review_query(selects, :workplace => reviewer.workplace)
        solutions.empty? ? works = nil : works = populate_works(solutions, :workplace => reviewer.workplace, :cluster => true)
      else
        return "Invalid Workplace"
      end      
    else
      # do a general lookup
      solutions = review_query(selects, params)
      solutions.empty? ? works = nil : works = populate_works(solutions, {:params => params, :cluster => true})
    end
    #puts works
    return works
  end  
  
  def populate_works(solutions, params={})
    # this method populates Work and Review objects, with optional clustering parameter
    works = []
    solutions.each do |solution|
      # use already defined Work if present and :cluster options given
      work = works.find {|w| w[:uri] == solution[:work_id].to_s} if params[:cluster]
      # or make a new Work object
      unless work
        # populate work object (Struct)
        work = Work.new(
              solution[:work_id].to_s,
              solution[:isbn] ? solution[:isbn].to_s.split(', ') : [params[:isbn]],
              solution[:book_title].to_s,
              solution[:book_id],
              solution[:author_id].to_s.split(', '),
              solution[:author].to_s,
              solution[:cover_url].to_s
              )
        work.reviews = []
      end
      # and fill with reviews
      # append text of reviews here to avvoid "Temporary row length exceeded error" in Virtuoso on sorting long texts
      review_uri = solution[:uri] ? solution[:uri] : params[:uri]
      query = QUERY.select(:review_text).where([review_uri, RDF::REV.text, :review_text, :context => REVIEWGRAPH])
      review_text = REPO.select(query).first[:review_text].to_s

      # populate review object (Struct)
      # map solutions to matching struct attributes
      review = Review.new
      review.members.each {|name| review[name] = solution[name] unless solution[name].nil? } 
      # map the rest
      review.title     = solution[:review_title].to_s
      review.teaser    = solution[:review_abstract].to_s
      review.text      = review_text
      review.reviewer  = solution[:reviewer_name].to_s
      review.source    = solution[:review_source].to_s
      review.subject   = work.isbn
      review.audience  = solution[:review_audience].to_s
      review.published = solution[:issued] ? true : false # published?
      
      # insert review object into work
      work.reviews << review
       
      # append to works array unless :cluster not set to true and work matching previous work
      unless params[:cluster] && works.any? {|w| w[:uri] == solution[:work_id].to_s}
        works << work
      # if :cluster not set and work not matching previous works
      else 
        works.map! {|w| (w[:uri] == solution[:work_id].to_s) ? work : w }
      end
    end
    works
  end
  
  def review_query(selects, params={})
    # this method queries RDF store with chosen selects and optional params from API
    # allowed params merged with params given in api
    api = Hashie::Mash.new(:uri => :uri, :isbn => :isbn, :title => :title, :author => :author, :author_id => :author_id, 
          :reviewer => :reviewer, :work => :work_id, :workplace => :workplace)
    api.merge!(params)
    puts params
    # do we have freetext searches on author/title?
    author_search   = params[:author] ? params[:author].gsub(/[[:punct:]]/, '').split(" ") : nil
    title_search    = params[:title] ? params[:title].gsub(/[[:punct:]]/, '').split(" ") : nil

    # query RDF store for work and reviews
    query = QUERY.select(*selects)
    query.group_digest(:author, ', ', 1000, 1)
    query.group_digest(:author_id, ', ', 1000, 1)
    query.group_digest(:isbn, ', ', 1000, 1) if api[:isbn] == :isbn
    query.group_digest(:review_audience, ',', 1000, 1)
    query.sample(:cover_url)
    query.distinct.where(
      [api[:uri], RDF.type, RDF::REV.Review, :context => REVIEWGRAPH],
      [api[:uri], RDF::DC.created, :created, :context => REVIEWGRAPH],
      [api[:uri], RDF::DC.modified, :modified, :context => REVIEWGRAPH],
      [api[:uri], RDF::REV.title, :review_title, :context => REVIEWGRAPH],
      [api[:uri], RDF::DC.abstract, :review_abstract, :context => REVIEWGRAPH],
      [:book_id, RDF::REV.hasReview, api[:uri], :context => BOOKGRAPH],
      [:book_id, RDF.type, RDF::FABIO.Manifestation, :context => BOOKGRAPH],
      [:book_id, RDF::BIBO.isbn, api[:isbn], :context => BOOKGRAPH],
      [:book_id, RDF::DC.title, :book_title, :context => BOOKGRAPH], # filtered by regex later
      # work & author
      [api[:work], RDF::FABIO.hasManifestation, :book_id, :context => BOOKGRAPH], 
      [api[:work], RDF::DC.creator, api[:author_id], :context => BOOKGRAPH],
      [api[:work], RDF::DC.creator, :author_id, :context => BOOKGRAPH],     # to get author_id in response
      [api[:author_id], RDF::FOAF.name, :author, :context => BOOKGRAPH],    # filtered by regex later
      # source
      [api[:uri], RDF::DC.source, :review_source_id, :context => REVIEWGRAPH],
      [:review_source_id, RDF::FOAF.name, :review_source, :context => APIGRAPH],
      # reviewer
      [api[:uri], RDF::REV.reviewer, api[:reviewer], :context => REVIEWGRAPH],
      [api[:reviewer], RDF::FOAF.name, :reviewer_name, :context => APIGRAPH],
      # audience
      [api[:uri], RDF::DC.audience, :review_audience_id, :context => REVIEWGRAPH],
      [:review_audience_id, RDF::RDFS.label, :review_audience, :context => REVIEWGRAPH]
      )
      # workplace
    if params[:workplace]
      query.where([api[:reviewer], RDF::ORG.memberOf, :workplace_id, :context => APIGRAPH],
      [:workplace_id, RDF::SKOS.prefLabel, api[:workplace], :context => APIGRAPH], # to get workplace in response
      [:workplace_id, RDF::SKOS.prefLabel, :workplace, :context => APIGRAPH])
    else
      query.optional([api[:reviewer], RDF::ORG.memberOf, :workplace_id, :context => APIGRAPH],
      [:workplace_id, RDF::SKOS.prefLabel, :workplace, :context => APIGRAPH])
    end
    query.filter('(lang(?review_audience) = "no")') 
    # optional attributes
    # NB! all these optionals adds extra ~2 sec to query
    query.optional([:book_id, RDF::FOAF.depiction, :cover_url, :context => BOOKGRAPH])
    query.optional([api[:uri], RDF::DC.issued, :issued, :context => REVIEWGRAPH]) # made optional to allow sorting by published true/false
    query.optional(
      [api[:reviewer], RDF::FOAF.account, :useraccount, :context => APIGRAPH],
      [:useraccount, RDF::FOAF.accountName, :accountName, :context => APIGRAPH]
      )      

    if author_search
      author_search.each do |author|
        query.filter("regex(?author, \"#{author}\", \"i\")")
      end
    end

    if title_search
      title_search.each do |title|
        query.filter("regex(?book_title, \"#{title}\", \"i\")")
      end
    end
    
    # filter by published parameter
    query.filter('bound(?issued)') if params[:published] == true
    query.filter('!bound(?issued)') if params[:published] == false
    
    # optimize query in virtuoso, drastically improves performance on optionals
    query.define('sql:select-option "ORDER"')
    # limit, offset and order by params
    params[:limit] ? query.limit(params[:limit]) : query.limit(10)
    query.offset(params[:offset]) if params[:offset]
    if /(author|title|reviewer|workplace|issued|modified|created)/.match(params[:order_by].to_s)
      if /(desc|asc)/.match(params[:order].to_s)  
        query.order_by("#{params[:order].upcase}(?#{params[:order_by]})")
      else
        query.order_by(params[:order_by].to_sym)
      end
    end
    
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
  end

  # this method creates a new Review object and inserts it into RDF store   
  def create(params)
    # find source
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source
    
    self.uri = source.autoincrement_resource(source.uri.to_s, resource = "review")
    return "Invalid UID" unless self.uri # break out if unable to generate unique ID
    
    work = Work.new.find(params)
    return "Invalid ISBN" unless work
    
    if params[:reviewer]
      params[:name] = params[:reviewer] # Reviewer takes :name parameter
      reviewer = Reviewer.new.find(:name => params[:reviewer])
      reviewer = Reviewer.new.create(params) if reviewer.nil? # create new if not found
      return "Invalid Reviewer ID" unless reviewer
    else
      # default to anonymous user
      reviewer = Reviewer.new.find(:uri => "http://data.deichman.no/reviewer/id_0")
    end
    
    params[:teaser] = String.new.clean_text(params[:teaser]) if params[:teaser]
    params[:text]   = String.new.clean_text(params[:text]) if params[:text] 
    params[:audience] ? params[:audience] = params[:audience] : params[:audience] = "adult"
    # update reviewer with new params
    self.members.each {|name| self[name] = params[name] unless params[name].nil? }
    self.source    = source.uri
    self.subject   = String.new.sanitize_isbn(params[:isbn])
    self.work_id   = work.first.uri
    self.book_id   = work.first.manifestation
    self.reviewer  = reviewer.uri
    self.workplace = reviewer.workplace
    self.created   = Time.now.xmlschema
    self.issued    = Time.now.xmlschema if params[:published]
    self.modified  = Time.now.xmlschema
    self
  end
  
  def update(params)
    # this method updates review and inserts into RDF store
    # first use api_key parameter to fetch source
    puts "update params: #{params.inspect}" if ENV['RACK_ENV'] == 'development'
    # find source
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source
    
    # make publish or unpublish switches
    unpublish = true if self.published && !params[:published]
    publish   = true if !self.published && params[:published]
    
    # Delete first
    # DO NOT delete DC.created and DC.issued properties on update unless published is changed
    deletequery = QUERY.delete([self.uri, :p, :o]).graph(REVIEWGRAPH)
    deletequery.where([self.uri, :p, :o])
    # MINUS not working properly until virtuoso 6.1.6!
    #deletequery.minus([self.uri, RDF::DC.created, :o])
    #deletequery.minus([self.uri, RDF::DC.issued, :o])
    deletequery.filter("?p != <#{RDF::DC.created.to_s}>")
    deletequery.filter("?p != <#{RDF::DC.issued.to_s}>") unless unpublish # keep issued unless unpublish state set
    
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    
    # Then update
    params.delete(:uri) # don't update uri!
    # reviewer
    reviewer = Reviewer.new.find(:name => self.reviewer)
    # delete empty params so they don't overwrite current review 
    params.each {|p| params.delete(p) if p.empty? }

    # update review with new params
    self.members.each {|name| self[name] = params[name] unless params[name].nil? }
    self.modified  = Time.now.xmlschema
    self.source    = source.uri
    self.reviewer  = reviewer.uri
    # change issued if publish state changed
    self.issued = Time.now.xmlschema if publish
    self.issued = nil if unpublish
    save # save changes to RDF store
    self    
  end

  # this method actually saves the review
  def save
    insert_statements = []
    insert_statements << RDF::Statement.new(self.uri, RDF.type, RDF::REV.Review)
    insert_statements << RDF::Statement.new(self.uri, RDF::DC.source, RDF::URI(self.source))
    insert_statements << RDF::Statement.new(self.uri, RDF::REV.title, RDF::Literal(self.title))
    insert_statements << RDF::Statement.new(self.uri, RDF::DC.abstract, RDF::Literal(self.teaser))
    insert_statements << RDF::Statement.new(self.uri, RDF::REV.text, RDF::Literal(self.text))
    # add link to manifetation by isbn
    insert_statements << RDF::Statement.new(self.uri, RDF::DC.subject, RDF::Literal(self.subject))
    insert_statements << RDF::Statement.new(self.uri, RDF::DC.created, RDF::Literal(self.created, :datatype => RDF::XSD.dateTime))
    insert_statements << RDF::Statement.new(self.uri, RDF::DC.issued, RDF::Literal(self.issued, :datatype => RDF::XSD.dateTime)) if self.issued
    insert_statements << RDF::Statement.new(self.uri, RDF::DC.modified, RDF::Literal(self.modified, :datatype => RDF::XSD.dateTime))

    # insert reviewer if found or created
    insert_statements << RDF::Statement.new(self.uri, RDF::REV.reviewer, self.reviewer)
  
    # Optionals - Audience
    unless self.audience
      # default to adult if not given
      insert_statements << RDF::Statement.new(self.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/adult"))
    else
      audiences = String.new.split_param(self.audience)
      audiences.each do |audience|
        if audience=="barn" || audience=="children"
          insert_statements << RDF::Statement.new(self.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/children"))
        elsif audience=="ungdom" || audience=="youth"
          insert_statements << RDF::Statement.new(self.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/youth"))
        elsif audience=="voksen" || audience=="adult"
          insert_statements << RDF::Statement.new(self.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/adult"))
        end
      end
    end
    query = QUERY.insert_data(insert_statements).graph(REVIEWGRAPH)
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    result = REPO.insert_data(query)
    
    # also insert hasReview property on work and book
    hasreview_statements  = []
    hasreview_statements << RDF::Statement.new(RDF::URI(self.work_id), RDF::REV.hasReview, self.uri)
    hasreview_statements << RDF::Statement.new(RDF::URI(self.book_id), RDF::REV.hasReview, self.uri)
    query                 = QUERY.insert_data(hasreview_statements).graph(BOOKGRAPH)
    result                = REPO.insert_data(query)
    self
  end
    
  # this method deletes review from RDF store
  def delete(params)
    # do nothing if review is not found
    return nil unless self.uri
    
    # check api_key
    source = Source.new.find_by_apikey(params[:api_key])
    return "Invalid api_key" unless source
        
    # then delete review, but only if source matches
    query  = QUERY.delete([self.uri, :p, :o])
    query.where([self.uri, RDF::DC.source, source.uri], [self.uri, :p, :o]).graph(REVIEWGRAPH)
    puts query
    result = REPO.delete(query)
    # and delete hasReview reference from work and manifestation
    query  = QUERY.delete([:workandbook, RDF::REV.hasReview, self.uri])
    query.where([:workandbook, RDF::REV.hasReview, self.uri]).graph(BOOKGRAPH)
    result = REPO.delete(query)
  end
end
