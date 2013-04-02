#encoding: utf-8

Review   = Struct.new(:uri, :title, :teaser, :text, :source, :reviewer, :workplace, 
            :audience, :subject, :work, :edition, :created, :issued, :modified, :published)

class Review
  
  # return all reviews, but with limits...
  def all(params={:limit=>10, :offset=>0, :order_by=>"created", :order=>"desc"})
    selects = [:uri, :work, :title, :teaser, :edition, :created, :issued, :modified, :source, :source_name, :subject, :reviewer, :reviewer_name, :accountName, :workplace, :workplace_name]
    solutions = review_query(selects, params)
    return nil if solutions.empty?
    reviews = populate_reviews(solutions)
  end
  
  # main method to find reviews, GET /api/reviews
  # params: uri, reviewer, workplace, published
  def find(params={})
    selects = [:uri, :work, :title, :teaser, :edition, :created, :issued, :modified, :source, :source_name, :subject, :reviewer, :reviewer_name, :accountName, :workplace, :workplace_name]

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
      end
    elsif params.has_key?(:work)
      begin 
        selects.delete(:work)
        uri = URI::parse(params[:work])
        uri = RDF::URI(uri)
        solutions = review_query(selects, :work => uri)
        return nil if solutions.empty?
      rescue URI::InvalidURIError
        return "Invalid URI"
      end
    elsif params.has_key?(:reviewer)
      reviewer = Reviewer.new.find(:uri => params[:reviewer])
      if reviewer
        solutions = review_query(selects, :reviewer => reviewer.uri)
      else
        return "Invalid Reviewer"
      end
    elsif params.has_key?(:workplace)
      reviewer = Workplace.new.find(:uri => params[:workplace])
      if reviewer
        solutions = review_query(selects, :workplace => reviewer.workplace)
      else
        return "Invalid Workplace"
      end      
    else
      # do a general lookup
      solutions = review_query(selects, params)
    end
    return nil if solutions.empty?
    reviews = populate_reviews(solutions)
  end  
  
  def populate_reviews(solutions)
    reviews = []
    solutions.each do |s|
      review = review_to_struct(s)
      reviews << review
    end
    reviews
  end

  # populates individual review
  def review_to_struct(s)
    review = s.to_hash.to_struct("Review")
    review.workplace = Workplace.new(s[:workplace], s[:workplace_name])
    review.source    = Source.new(s[:source], s[:source_name])
    review.reviewer  = Reviewer.new(s[:reviewer], s[:reviewer_name])
    review.audience  = s[:audience_name].to_s.split(',')
    review.published = s[:issued] ? true : false # published?
    ## query text of reviews here to avvoid "Temporary row length exceeded error" in Virtuoso on sorting long texts
    query = QUERY.select(:text).from(REVIEWGRAPH).where([review.uri, RDF::REV.text, :text])
    review.text = REPO.select(query).first[:text].to_s
    ## end append text
    review
  end
  
  ### methods for inserting review into Work
  def reviews_to_works(reviews)
    works = []
    reviews.each {|r| work = r.add_work; works << work.first if work }
    works
  end

  # private methods
  # this method adds review to work
  def add_work
    work = find_work
    return nil unless work
    work.first.reviews = [self]
    work
  end
  
  
  # this method simply looks up work
  def find_work
    work = Work.new.find(:uri => self.work, :reviews => false)
  end
  
  # deprecated
  def old_populate_works(solutions, params={})
    # this method populates Work and Review objects, with optional clustering parameter
    works = []
    solutions.each do |solution|
      # use already defined Work if present and :cluster options given
      work = works.find {|w| w[:uri] == solution[:work_id].to_s} if params[:cluster]
      # or make a new Work object
      unless work
        # populate work object (Struct)
        ## HERE!
        work = Work.new
        work.uri   = solution[:work_id].to_s
        work.isbns = (solution[:isbn] ? solution[:isbn].to_s.split(', ') : [params[:isbn]])
        work.title = solution[:book_title].to_s
        work.editions = solution[:book_id]
        work.authors = solution[:author_id].to_s.split(', ')
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
      review.subject   = work.isbns
      review.audience  = solution[:review_audience].to_s
      review.published = solution[:issued] ? true : false # published?
      
      # insert review object into work
      work.reviews << review
       
      # append to works array unless :cluster not set to true and work matching previous work
      unless params[:cluster] && works.any? {|w| w[:uri] == solution[:work_id].to_s}
        works << work
      # if :cluster is set true and work not matching previous works
      else 
        works.map! {|w| (w[:uri] == solution[:work_id].to_s) ? work : w }
      end
    end
    works
  end
  
  # only allow query on uri, work, reviewer and workplace. Rest should query on work
  def review_query(selects, params)
    api = Hashie::Mash.new(:uri => :uri, :reviewer => :reviewer, :workplace => :workplace, :work=> :work)
    api.merge!(params)
    puts "params: #{params}" if ENV['RACK_ENV'] == 'development'
    
    # query RDF store for reviews
    query = QUERY.select(*selects)
    query.group_digest(:audience, ',', 1000, 1)
    query.group_digest(:audience_name, ',', 1000, 1)
    query.from(REVIEWGRAPH)
    query.from_named(BOOKGRAPH)
    query.from_named(APIGRAPH)
    query.distinct.where(
      [api[:uri], RDF.type, RDF::REV.Review],
      [api[:uri], RDF::DC.created, :created],
      [api[:uri], RDF::DC.modified, :modified],
      [api[:uri], RDF::REV.title, :title],
      [api[:uri], RDF::DC.abstract, :teaser],
      [api[:uri], RDF::DC.subject, :subject])
    query.where.graph2(BOOKGRAPH).group(
      [:edition, RDF::REV.hasReview, api[:uri]],
      [:edition, RDF.type, RDF::FABIO.Manifestation],
      [api[:work], RDF::FABIO.hasManifestation, :edition])
      # source
    query.where([api[:uri], RDF::DC.source, :source],
      [:source, RDF::FOAF.name, :source_name, :context => APIGRAPH],
      # reviewer
      [api[:uri], RDF::REV.reviewer, api[:reviewer]],
      [api[:reviewer], RDF::FOAF.name, :reviewer_name, :context => APIGRAPH],
      # audience
      [api[:uri], RDF::DC.audience, :audience],
      [:audience, RDF::RDFS.label, :audience_name]
      )
      # workplace
    if params[:workplace]
      query.where([api[:reviewer], RDF::ORG.memberOf, api[:workplace], :context => APIGRAPH],
        [api[:workplace], RDF::SKOS.prefLabel, api[:workplace], :context => APIGRAPH], # to get workplace in response
        [api[:workplace], RDF::SKOS.prefLabel, :workplace_name, :context => APIGRAPH])
    else
      query.optional([api[:reviewer], RDF::ORG.memberOf, api[:workplace], :context => APIGRAPH],
        [api[:workplace], RDF::SKOS.prefLabel, :workplace_name, :context => APIGRAPH])
    end
    query.filter('(lang(?audience_name) = "no")') 
    # optional attributes
    query.optional([api[:uri], RDF::DC.issued, :issued]) # made optional to allow sorting by published true/false
    query.optional(
      [api[:reviewer], RDF::FOAF.account, :useraccount, :context => APIGRAPH],
      [:useraccount, RDF::FOAF.accountName, :accountName, :context => APIGRAPH]
      )      
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
    
    puts "#{query.pp}" if ENV['RACK_ENV'] == 'development'
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
      params[:accountName] = params[:reviewer] # Reviewer takes :name parameter
      reviewer = Reviewer.new.find(:accountName => params[:reviewer])
      reviewer = Reviewer.new.create(:accountName => params[:accountName], 
                                     :api_key => params[:api_key]) if reviewer.nil? # create new if not found
      return "Invalid Reviewer ID" unless reviewer
      reviewer.save
    else
      # default to anonymous user
      reviewer = Reviewer.new.find(:uri => "http://data.deichman.no/reviewer/id_0")
    end
    
    params[:teaser] = String.new.clean_text(params[:teaser]) if params[:teaser]
    params[:text]   = String.new.clean_text(params[:text]) if params[:text] 
    # make sure we have audience!
    if params[:audience]
      if /([Bb]arn|[Un]gdom|[Vv]oksen|[Cc]hildren|[Yy]outh|[Aa]dult)/.match(params[:audience].to_s)
        params[:audience].downcase! 
      else
        params[:audience] = "adult"
      end
    else 
      params[:audience] = "adult"
    end
    # create review from params
    self.members.each {|name| self[name] = params[name] unless params[name].nil? }
    self.source    = source.uri
    self.subject   = String.new.sanitize_isbn(params[:isbn])
    self.work      = work.first.uri
    self.edition   = work.first.editions.first.uri
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
    # MINUS not working properly as of virtuoso 6.1.6!
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
    reviewer = Reviewer.new.find(:uri => self.reviewer.uri)
    params[:teaser] = String.new.clean_text(params[:teaser]) if params[:teaser]
    params[:text]   = String.new.clean_text(params[:text]) if params[:text] 
    # make sure we have audience!
    if params[:audience]
      if /([Bb]arn|[Un]gdom|[Vv]oksen|[Cc]hildren|[Yy]outh|[Aa]dult)/.match(params[:audience].to_s)
        params[:audience].downcase! 
      else
        params[:audience] = "adult"
      end
    else
      # don't update audience unless match above
      params[:audience] = nil
    end
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
      if self.audience.is_a?(String)
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
      else
        self.audience.each {|a| insert_statements << RDF::Statement.new(self.uri, RDF::DC.audience, self.audience.uri) }
      end
    end
    query = QUERY.insert_data(insert_statements).graph(REVIEWGRAPH)
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    result = REPO.insert_data(query)
    
    # also insert hasReview property on work and book
    hasreview_statements  = []
    hasreview_statements << RDF::Statement.new(RDF::URI(self.work), RDF::REV.hasReview, self.uri)
    hasreview_statements << RDF::Statement.new(RDF::URI(self.edition), RDF::REV.hasReview, self.uri)
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
