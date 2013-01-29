#encoding: utf-8
require 'rdf/n3'
require "rdf/virtuoso"
require "sanitize"

# Structs are simple classes with fixed sequence of instance variables
Work = Struct.new(:title, :isbn, :book_id, :work_id, :author_id, :author, :cover_url, :reviews)
Review = Struct.new(:uri, :title, :teaser, :text, :source, :reviewer, :workplace, :audience, :created, :issued, :modified)

require_relative './string_replace.rb'
require_relative "./init.rb"
require_relative "./vocabularies.rb"
require_relative "./reviewer.rb"
require_relative "./source.rb"

class Review
  # main method to find reviews, GET /api/review
  # params: uri, isbn, title, author, reviewer, work
  def find_reviews(params = {})
    selects     = [:uri, :work_id, :book_id, :book_title, :created, :issued, :modified, :review_title, :review_abstract, :review_source, :reviewer_name, :accountName, :workplace]

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
          selects.delete(:uri)
          uri = URI::parse(params[:uri])
          uri = RDF::URI(uri)
          solutions = review_query(selects, :uri => uri)
          solutions.empty? ? works = nil : works = populate_works(solutions, :uri => uri, :cluster => true) 
        rescue URI::InvalidURIError
          return "Invalid URI"
        end
      end
    elsif params.has_key?(:isbn)
      isbn      = sanitize_isbn("#{params[:isbn]}")
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
      reviewer = find_reviewer(:reviewer => params[:reviewer])
      if reviewer
        solutions = review_query(selects, :reviewer => reviewer[:reviewer_id])
        solutions.empty? ? works = nil : works = populate_works(solutions, :reviewer => reviewer[:reviewer_id], :cluster => true)
      else
        return "Invalid Reviewer"
      end
    elsif params.has_key?(:workplace)
      reviewer = find_reviewer(:workplace => params[:workplace])
      if reviewer
        solutions = review_query(selects, :workplace => reviewer[:workplace])
        solutions.empty? ? works = nil : works = populate_works(solutions, :workplace => reviewer[:workplace], :cluster => true)
      else
        return "Invalid Workplace"
      end      
    else
      # do a general lookup
      solutions = review_query(selects, params)
      solutions.empty? ? works = nil : works = populate_works(solutions, {:params => params, :cluster => true})
    end
    return works
  end  
  
  def populate_works(solutions, params={})
    # this method populates Work and Review object, with optional clustering parameter
    works = []
    solutions.each do |solution|
      # use already defined Work if present and :cluster options given
      work = works.find {|w| w[:work_id] == solution[:work_id].to_s} if params[:cluster]
      # or make a new Work object
      unless work
        # populate work object (Struct)
        work = Work.new(
                        solution[:book_title].to_s,
                        solution[:isbn] ? solution[:isbn].to_s.split(', ') : [params[:isbn]],
                        solution[:book_id],
                        solution[:work_id].to_s,
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
      # reviewer
      reviewer = solution[:reviewer_name] ? solution[:reviewer_name].to_s : solution[:reviewer_nick].to_s 
      
      # populate review object (Struct)
      review = Review.new(
                      solution[:uri] ? solution[:uri].to_s : review_uri,
                      solution[:review_title].to_s,
                      solution[:review_abstract].to_s,
                      review_text,
                      solution[:review_source].to_s,
                      reviewer,
                      solution[:workplace].to_s,
                      solution[:review_audience].to_s,
                      solution[:created].to_s,
                      solution[:issued].to_s,
                      solution[:modified].to_s
                      )
      # insert review object into work
      work.reviews << review
       
      # append to works array unless :cluster not set to true and work matching previous work
      unless params[:cluster] && works.any? {|w| w[:work_id] == solution[:work_id].to_s}
        works << work
      # if :cluster not set and work not matching previous works
      else 
        works.map! {|w| (w[:work_id] == solution[:work_id].to_s) ? work : w }
      end
    end
    works
  end
  
  def review_query(selects, params={})
    # this method queries RDF store with chosen selects and optional params from API
    # allowed params merged with params given in api
    api = {:uri => :uri, :isbn => :isbn, :title => :title, :author => :author, :author_id => :author_id, :reviewer => :reviewer, :work => :work_id, :workplace => :workplace}
    api.merge!(params)
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
      [api[:uri], RDF::DC.issued, :issued, :context => REVIEWGRAPH],
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
  
  def create(params)
    # this method creates a new Review object and inserts it into RDF store 
    # first use api_key parameter to fetch source
    source = find_source_by_apikey(params[:api_key])
    return "Invalid api_key" unless source
    
    # find work based on isbn
    isbn = sanitize_isbn("#{params[:isbn]}")

    # quick lookup, don't need reviewer or source
    query = QUERY.select(:book_id, :book_title, :work_id)
    query.group_digest(:author_id, ', ', 1000, 1)
    query.group_digest(:author, ', ', 1000, 1)
    query.from(BOOKGRAPH)
    query.where(
      [:book_id, RDF::BIBO.isbn, "#{isbn}"],
      [:book_id, RDF.type, RDF::BIBO.Document],
      [:book_id, RDF::DC.title, :book_title],
      [:author_id, RDF::FOAF.name, :author],
      [:work_id, RDF::FABIO.hasManifestation, :book_id],
      [:work_id, RDF::DC.creator, :author_id]
      )
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)

    # populate review attributes
    unless solutions.empty?
      # increment review id
      uri = autoincrement_resource(source)
      return "Invalid URI" unless uri
      
      if params[:reviewer]
        # lookup reviewer by nick or full name
        reviewer = find_reviewer(:reviewer => params[:reviewer])
        unless reviewer
          # create new reviewer if not found in base
          reviewer = create_reviewer(source, params[:reviewer])
          return "Invalid Reviewer ID" unless reviewer # break out if unable to generate ID
        end
      else 
        reviewer = {}
      end
      work = Work.new(
          solutions.first[:book_title],
          isbn,
          solutions.first[:book_id],
          solutions.first[:work_id],
          solutions.first[:author_id].to_s.split(', '),
          solutions.first[:author]
          )
      work.reviews = []
      review = Review.new(
          uri,
          params[:title],
          clean_text(params[:teaser]),
          clean_text(params[:text]),
          source,
          reviewer[:reviewer_id],
          reviewer[:workplace],
          params[:audience] ? params[:audience] : "adult",
          Time.now.xmlschema, # created
          Time.now.xmlschema, # issued
          Time.now.xmlschema  # modified
          )
      work.reviews << review
    else
      return "Invalid ISBN" # break out if isbn returns no hits
    end    
    
    insert_statements = []
    insert_statements << RDF::Statement.new(review.uri, RDF.type, RDF::REV.Review)
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.source, RDF::URI(review.source))
    insert_statements << RDF::Statement.new(review.uri, RDF::REV.title, RDF::Literal(review.title))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.abstract, RDF::Literal(review.teaser))
    insert_statements << RDF::Statement.new(review.uri, RDF::REV.text, RDF::Literal(review.text))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.subject, RDF::Literal(work.isbn))
    #insert_statements << RDF::Statement.new(review.uri, RDF::DEICHMAN.basedOnManifestation, RDF::URI(work.book_id))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.created, RDF::Literal(review.created, :datatype => RDF::XSD.dateTime))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.issued, RDF::Literal(review.issued, :datatype => RDF::XSD.dateTime))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.modified, RDF::Literal(review.modified, :datatype => RDF::XSD.dateTime))

    # insert reviewer if found or created
    insert_statements << RDF::Statement.new(review.uri, RDF::REV.reviewer, RDF::URI("#{reviewer[:reviewer_id]}")) if reviewer[:reviewer_id]
  
    # Optionals - Audience, Maybe better to lookup labels on the fly?
    unless review.audience
      # default to adult if not given
      insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/adult"))
    else
      audiences = split_param(review.audience)
      audiences.each do |audience|
        case audience
        when 'barn' || 'children'
          insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/children"))
        when 'ungdom' || 'youth'
          insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/youth"))
        when 'voksen' || 'adult'
          insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/adult"))
        end
      end
    end

    query = QUERY.insert_data(insert_statements).graph(REVIEWGRAPH)
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    result = REPO.insert_data(query)
    
    # also insert hasReview property on work and book
    hasreview_statements  = []
    hasreview_statements << RDF::Statement.new(RDF::URI(work.work_id), RDF::REV.hasReview, review.uri)
    hasreview_statements << RDF::Statement.new(RDF::URI(work.book_id), RDF::REV.hasReview, review.uri)
    query                 = QUERY.insert_data(hasreview_statements).graph(BOOKGRAPH)
    result                = REPO.insert_data(query)
    return work
  end
  
  def update(params)
    # this method updates review and inserts into RDF store
    # first use api_key parameter to fetch source
    puts "update params: #{params.inspect}" if ENV['RACK_ENV'] == 'development'
    source = find_source_by_apikey(params[:api_key])
    return "Invalid api_key" unless source
    
    work   = self.find_reviews(params).first
    review = work.reviews.first 
    # handle modified variables from given params
    # puts "params before:\n #{params}"
    unwanted_params = ['uri', 'api_key', 'route_info', 'method', 'path']
    unwanted_params.each {|d| params.delete(d)}
    
    #puts "params after:\n #{params}"
    
    puts "before update:\n#{work}" if ENV['RACK_ENV'] == 'development'
    # update review with new params
    params.each{|k,v| review[k] = v}
    #new = params.to_struct "Review"
    # set modified time
    review.modified = Time.now.xmlschema
    review.teaser   = clean_text(review.teaser)
    review.text     = clean_text(review.text)
    puts "after update:\n#{work}" if ENV['RACK_ENV'] == 'development'
    
    # SPARQL UPDATE
    # DO NOT delete DC.created and DC.issued properties on update
    deletequery = QUERY.delete([review.uri, :p, :o]).graph(REVIEWGRAPH)
    deletequery.where([review.uri, :p, :o])
    # MINUS not working properly until virtuoso 6.1.6!
    #deletequery.minus([review.review_id, RDF::DC.created, :o])
    #deletequery.minus([review.review_id, RDF::DC.issued, :o])
    deletequery.filter("?p != <#{RDF::DC.created.to_s}>")
    deletequery.filter("?p != <#{RDF::DC.issued.to_s}>")
    
    puts "deletequery:\n #{deletequery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    
    insert_statements = []
    insert_statements << RDF::Statement.new(review.uri, RDF.type, RDF::REV.Review)
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.source, RDF::URI(source))
    insert_statements << RDF::Statement.new(review.uri, RDF::REV.title, RDF::Literal(review.title))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.abstract, RDF::Literal(review.teaser))
    insert_statements << RDF::Statement.new(review.uri, RDF::REV.text, RDF::Literal(review.text))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.subject, RDF::Literal(work.isbn))
    insert_statements << RDF::Statement.new(review.uri, RDF::DEICHMAN.basedOnManifestation, RDF::URI(work.book_id))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.modified, RDF::Literal(review.modified, :datatype => RDF::XSD.dateTime))

    # Optionals - Reviewer lookup in APIGRAPH for full name or nick
    if review.reviewer
      query = QUERY.select(:reviewer_id).from(APIGRAPH)
      query.where([:reviewer_id, RDF.type, RDF::FOAF.Person])
      # reviewer by foaf name
      query.optional([:reviewer_id, RDF::FOAF.name, "#{params[:reviewer]}"])
      # reviewer by accountname
      query.optional([:reviewer_id, RDF::FOAF.account, :useraccount],
                      [:useraccount, RDF::FOAF.accountName, "#{params[:reviewer]}"])
      solutions = REPO.select(query)
      if solutions
        insert_statements << RDF::Statement.new(review.uri, RDF::REV.reviewer, RDF::URI("#{solutions.first[:reviewer_id]}"))
      end
    end 
        
    # Optionals - audience
    unless review.audience
      # default to adult if not given
      insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/adult"))
    else
      audiences = split_param(review.audience)
      audiences.each do |audience|
        case audience
        when 'barn' || 'children'
          insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/children"))
        when 'ungdom' || 'youth'
          insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/youth"))
        when 'voksen' || 'adult'
          insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/adult"))
        end
      end
    end
    
    insertquery = QUERY.insert_data(insert_statements).graph(REVIEWGRAPH)
    puts "insertquery:\n #{insertquery}" if ENV['RACK_ENV'] == 'development'
    result = REPO.insert_data(insertquery)
    puts "insert result:\n #{result}" if ENV['RACK_ENV'] == 'development'
    work
  end
  
  def delete(params = {})
    # this method deletes review from RDF store
    # first use api_key parameter to fetch source
    review_source = find_source_by_apikey(params[:api_key])
    return "Invalid api_key" unless review_source
        
    source = RDF::URI(review_source)
    uri    = RDF::URI(params[:uri])
    
    # then delete review, but only if source matches
    query  = QUERY.delete([uri, :p, :o]).where([uri, RDF::DC.source, source], [uri, :p, :o]).graph(REVIEWGRAPH)
    result = REPO.delete(query)
    # and delete hasReview reference from work
    query  = QUERY.delete([:work, RDF::REV.hasReview, uri])
    query.where([:work, RDF::REV.hasReview, uri]).graph(BOOKGRAPH)
    result = REPO.delete(query)
  end

  # string methods
  def split_param(param)
    # split values in param separated with comma or slash or pipe and return array
    params = param.downcase.gsub(/\s+/, '').split(/,|\/|\|/)
  end
  
  def clean_text(text)
    # this method cleans html tags and other presentation awkwardnesses
    # first remove all but whitelisted html elements
    sanitized = Sanitize.clean(text, :elements => %w[p pre small em i strong strike b blockquote q cite code br h1 h2 h3 h4 h5 h6],
      :attributes => {'span' => ['class']})
    # then strip newlines, tabs carriage returns and return pretty text
    result = sanitized.gsub(/\s+/, ' ').squeeze(' ')
  end  
  
  def sanitize_isbn(isbn)
    isbn.strip.gsub(/[^0-9xX]/, '')
  end
end

# patched Struct and Hash classes to allow easy conversion to/from JSON and Hash
class Struct
  def to_map
    # this method returns Hash map of Struct
    map = Hash.new
    self.members.each { |m| map[m] = self[m] }
    # strip out empty struct values
    map.reject! {|k,v| v.strip.empty? if v.is_a?(String) && v.respond_to?('empty?')}
    map
  end
  def to_json(*a)
    to_map.to_json(*a)
  end
end

class Hash
  def to_struct(name)
    #This method returns struct object "name" from hash object
    Struct.new(name, *keys).new(*values)
  end
end

