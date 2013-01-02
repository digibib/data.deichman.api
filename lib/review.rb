#encoding: utf-8
require 'rdf/n3'
require "rdf/virtuoso"
require "sanitize"

require_relative './string_replace.rb'
require_relative "./init.rb"
require_relative "./vocabularies.rb"

# Structs are simple classes with fixed sequence of instance variables
Work = Struct.new(:title, :isbn, :book_id, :work_id, :author, :cover_url, :reviews)
Review = Struct.new(:uri, :title, :teaser, :text, :source, :reviewer, :audience, :created, :issued, :modified) do

  # main method to find reviews, GET /api/review
  # params: uri, isbn, title, author, reviewer, work
  def find_reviews(params = {})
    selects     = [:uri, :work_id, :book_title, :created, :issued, :modified, :review_title, :review_abstract, :review_source, :review_audience, :reviewer_name, :accountName]
    
    if params.has_key?(:uri)
      begin 
        selects.delete(:uri)
        uri = URI::parse(params[:uri])
        uri = RDF::URI(uri)
        solutions = review_query(selects, :uri => uri)
      rescue URI::InvalidURIError
        return "Invalid URI"
      end
    elsif params.has_key?(:isbn)
      isbn          = sanitize_isbn("#{params[:isbn]}")
      solutions = review_query(selects, :isbn => isbn)
    elsif params.has_key?(:work)
      begin 
        selects.delete(:work_id)
        uri = URI::parse(params[:work])
        uri = RDF::URI(uri)
        solutions = review_query(selects, :work => uri)
      rescue URI::InvalidURIError
        return "Invalid URI"
      end    
    elsif params.has_key?(:reviewer)
      solutions = review_query(selects, :reviewer => params[:reviewer])
    else
      solutions = review_query(selects, :author => params[:author], :title => params[:title])
    end

    works = []
    unless solutions.empty?
        solutions.each do |solution|
          # use already defined Work if present
          work = works.find {|w| w[:work_id] == solution[:work_id].to_s}
          # or make a new Work object
          unless work
            work = Work.new(
                            solution[:book_title].to_s,
                            solution[:isbn] ? solution[:isbn].to_s : isbn,
                            solution[:book_id].to_s,
                            solution[:work_id].to_s,
                            solution[:author].to_s,
                            solution[:cover_url].to_s
                            )
            work.reviews = []
          end
          # and fill with reviews
          # append text of reviews here to avvoid "Temporary row length exceeded error" in Virtuoso on sorting long texts
          review_uri = solution[:uri] ? solution[:uri] : uri
          query = QUERY.select(:review_text).where([review_uri, RDF::REV.text, :review_text, :context => REVIEWGRAPH])
          review_text = REPO.select(query).first[:review_text].to_s
          # reviewer
          reviewer = solution[:reviewer_name] ? solution[:reviewer_name].to_s : solution[:reviewer_nick].to_s 
          
          review = Review.new(
                          solution[:uri] ? solution[:uri].to_s : uri,
                          solution[:review_title].to_s,
                          solution[:review_abstract].to_s,
                          #solution[:review_text].to_s,
                          review_text,
                          solution[:review_source].to_s,
                          reviewer,
                          solution[:review_audience].to_s,
                          solution[:created].to_s,
                          solution[:issued].to_s,
                          solution[:modified].to_s
                          )
          work.reviews << review

        # append to or replace work in works array
        unless works.any? {|w| w[:work_id] == solution[:work_id].to_s}
          works << work
        else
          works.map! {|w| (w[:work_id] == solution[:work_id].to_s) ? work : w }
        end

      end
    end
    works
  end  
  
  def review_query(selects, params={})
    # allowed params merged with params given in api
    api = {:uri => :uri, :isbn => :isbn, :title => :title, :author => :author, :reviewer => :reviewer, :work => :work_id}
    api.merge!(params)
    # do we have freetext searches on author/title?
    author_search   = params[:author] ? params[:author].gsub(/[[:punct:]]/, '').split(" ") : nil
    title_search    = params[:title] ? params[:title].gsub(/[[:punct:]]/, '').split(" ") : nil

    # query RDF store for work and reviews
    query = QUERY.select(*selects)
    query.group_digest(:author, ', ', 1000, 1)
    query.group_digest(:isbn, ', ', 1000, 1) if api[:isbn] == :isbn
    query.sample(:book_id, :cover_url)
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
      [api[:work], RDF::FABIO.hasManifestation, :book_id, :context => BOOKGRAPH], 
      [api[:work], RDF::DC.title, :book_title, :context => BOOKGRAPH], # filtered by regex later
      [api[:work], RDF::DC.creator, :author_id, :context => BOOKGRAPH],
      [:author_id, RDF::FOAF.name, :author, :context => BOOKGRAPH]    # filtered by regex later
      )
    # optional attributes
    # NB! all these optionals adds extra ~2 sec to query
    query.optional([:book_id, RDF::FOAF.depiction, :cover_url, :context => BOOKGRAPH])
    # review source
    query.optional([api[:uri], RDF::DC.source, :review_source_id, :context => REVIEWGRAPH],
      [:review_source_id, RDF::FOAF.name, :review_source, :context => APIGRAPH])
    # reviewer by foaf name
    query.optional([api[:uri], RDF::REV.reviewer, :reviewer_id, :context => REVIEWGRAPH],
      [:reviewer_id, RDF::FOAF.name, :reviewer_name, :context => APIGRAPH])
    # reviewer by accountname
    query.optional(
      [api[:uri], RDF::REV.reviewer, :reviewer_id, :context => REVIEWGRAPH],
      [:reviewer_id, RDF::FOAF.account, :useraccount, :context => APIGRAPH],
      [:useraccount, RDF::FOAF.accountName, :accountName, :context => APIGRAPH]
      )      
    # review audience
    query.optional([api[:uri], RDF::DC.audience, :review_audience_id, :context => REVIEWGRAPH],
      [:review_audience_id, RDF::RDFS.label, :review_audience, :context => REVIEWGRAPH]) 
    query.filter('(lang(?review_audience) = "no" || !bound(?review_audience))') 
    # reviewer workplace -- not yet implemented
    #query.optional(
    #  [api[:uri], RDF::REV.reviewer, :reviewer_id, :context => REVIEWGRAPH],
    #  [:workplace_id, RDF::FOAF.member, :reviewer_id, :context => APIGRAPH],
    #  [:workplace_id, RDF::FOAF.name, :reviewer_workplace, :context => APIGRAPH])

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
    
    query.filter("?reviewer_id = \"#{api[:reviewer]}\" || 
                  ?reviewer_name = \"#{api[:reviewer]}\" || 
                  ?reviewer_nick = \"#{api[:reviewer]}\"") if params[:reviewer]
    
    # optimize query in virtuoso, drastically improves performance on optionals
    query.define('sql:select-option "ORDER"')
    query.limit(50)

    puts query
    solutions = REPO.select(query)
  end
  
  def find_source_by_apikey(api_key)
    # fetch source by api key in protected graph
    # each source needs three statements: 
    # <source> a rdfs:Resource ;
    #          rdfs:label "Label" ;
    #          deichman:apikey "apikey" .    
    query = QUERY.select(:source).from(APIGRAPH)
    query.where(
      [:source, RDF.type, RDF::FOAF.Document], 
      [:source, RDF::FOAF.name, :label],
      [:source, RDF::DEICHMAN.apikey, "#{api_key}"])
    query.limit(1)
    #puts query
    solutions = REPO.select(query)
    return nil if solutions.empty?
    source = solutions.first[:source]
  end
  
  def find_reviewer(reviewer)
    # looks in apigraph for reviewer by either reviewer's foaf:name or reviewer account's foaf:accountName
    query = QUERY.select(:reviewer_id).from(APIGRAPH)
    query.where([:reviewer_id, RDF.type, RDF::FOAF.Person])
    # reviewer by foaf name
    query.optional([:reviewer_id, RDF::FOAF.name, :reviewer_name])
    # reviewer by accountname
    query.optional([:reviewer_id, RDF::FOAF.account, :useraccount],
                    [:useraccount, RDF::FOAF.accountName, :accountName])
    query.filter("?reviewer_name = \"#{reviewer}\" || ?reviewer_nick = \"#{reviewer}\"")
    #puts query                    
    solutions = REPO.select(query)
    #puts solutions.inspect
    return nil if solutions.empty?
    reviewer_id = solutions.first[:reviewer_id]
  end

  def create_reviewer(source, reviewer)
    # create a new reviewer id, Reviewer and Account
    reviewer_id = autoincrement_resource(source, resource = "reviewer")
    return nil unless reviewer_id # break out if unable to generate ID
    account_id = autoincrement_resource(source, resource = "account")
    return nil unless account_id # break out if unable to generate ID
    account      = RDF::URI(account_id)
    account_name = "#{reviewer.urlize}"
    
    insert_statements = []
    # create Reviewer (foaf:Person)
    insert_statements << RDF::Statement.new(reviewer_id, RDF.type, RDF::FOAF.Person)
    insert_statements << RDF::Statement.new(reviewer_id, RDF::FOAF.name, "#{reviewer}")
    insert_statements << RDF::Statement.new(reviewer_id, RDF::FOAF.account, account)
    # create Account (sioc:UserAccount) with dummy password and status: ActivationNeeded
    insert_statements << RDF::Statement.new(account, RDF.type, RDF::SIOC.UserAccount)
    insert_statements << RDF::Statement.new(account, RDF::FOAF.accountName, "#{account_name}")
    insert_statements << RDF::Statement.new(account, RDF::FOAF.accountServiceHomepage, RDF::URI("#{source}"))
    insert_statements << RDF::Statement.new(account, RDF::ACC.password, "#{account_name}123")
    insert_statements << RDF::Statement.new(account, RDF::ACC.status, RDF::ACC.ActivationNeeded)
    insert_statements << RDF::Statement.new(account, RDF::ACC.lastActivity, RDF::Literal(Time.now.xmlschema, :datatype => RDF::XSD.dateTime))
    query = QUERY.insert_data(insert_statements).graph(APIGRAPH)
    puts "#{query}"
    result = REPO.insert_data(query)
    puts result
    return reviewer_id
  end  
  
  def autoincrement_resource(source, resource = "review")
    # This method uses Virtuoso's internal sequence function to generate unique IDs on resources from api_key mapped to source
    # sql:sequence_next("GRAPH_IDENTIFIER") => returns next sequence from GRAPH_IDENTIFIER
    # sql:sequence_set("GRAPH_IDENTIFIER", new_sequence_number, ignoreiflowerthancurrent_boolean) => sets sequence number
    # get unique sequential id by CONSTRUCTing an id based on source URI
    # defaults to "review" if no resource name given
    # nb: to reset count use sequence_set instead, with a CONSTRUCT iri f.ex. like this:
    # `iri(bif:CONCAT("http://data.deichman.no/deichman/reviews/id_", str(bif:sequence_set ('#{GRAPH_IDENTIFIER}', 0, 0)) ) )`
    if source
      # parts to compose URI base for resource
      parts = []
      parts << "'#{BASE_URI}'"
      parts << "bif:REPLACE(str(?source), 'http://data.deichman.no/source/', '/')" if resource == "review"
      parts << "'/#{resource}'"
      parts << "'/id_'"
      
      # choose sequence origin, either from review source or from resource
      resource == "review" ? parts << "str(bif:sequence_next ('#{source}'))" : parts << "str(bif:sequence_next ('#{resource}'))"
      
      # CONSTRUCT query  
      query = "CONSTRUCT { `iri( bif:CONCAT( "
      query << parts.join(', ').to_s
      query << " ) )` a <#{RDF::DEICHMAN.DummyClass}> } "
      query << "WHERE { <#{source}> a <#{RDF::FOAF.Document}> ; <#{RDF::FOAF.name}> ?name . ?source a <#{RDF::FOAF.Document}> ; <#{RDF::FOAF.name}> ?name }"
      query << " ORDER BY(?source) LIMIT 1"
      puts "#{query}"
      
      solutions = REPO.construct(query)
      
      return nil if solutions.empty?
      resource_id = solutions.first[:s]
    end
  end
    
  def create(params)
    # create new review here
    # first use api_key parameter to fetch source
    source = find_source_by_apikey(params[:api_key])
    return "Invalid api_key" unless source
    
    # find work based on isbn
    isbn = sanitize_isbn("#{params[:isbn]}")

    query = QUERY.select(:book_id, :book_title, :work_id, :author)
    query.from(BOOKGRAPH)
    query.where(
      [:book_id, RDF::BIBO.isbn, "#{isbn}"],
      [:book_id, RDF.type, RDF::BIBO.Document],
      [:book_id, RDF::DC.title, :book_title],
      [:book_id, RDF::DC.creator, :creator],
      [:creator, RDF::FOAF.name, :author],
      [:work_id, RDF::FABIO.hasManifestation, :book_id]
      )
    #puts "#{query}"
    solutions = REPO.select(query)

    # populate review attributes
    unless solutions.empty?
      # increment review id
      uri = autoincrement_resource(source)
      return "Invalid URI" unless uri
      
      if params[:reviewer]
        # lookup reviewer by nick or full name
        reviewer_id = find_reviewer(params[:reviewer])
        # create new if not found
        reviewer_id = create_reviewer(source, params[:reviewer]) unless reviewer_id
        return "Invalid Reviewer ID" unless reviewer_id # break out if unable to generate ID
      end
      work = Work.new(
          solutions.first[:book_title],
          isbn,
          solutions.first[:book_id],
          solutions.first[:work_id],
          solutions.first[:author]
          )
      work.reviews = []
      review = Review.new(
          uri,
          params[:title],
          clean_text(params[:teaser]),
          clean_text(params[:text]),
          source,
          reviewer_id,
          params[:audience] ? params[:audience] : nil,
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
    insert_statements << RDF::Statement.new(review.uri, RDF::REV.reviewer, RDF::URI("#{reviewer_id}")) if reviewer_id
=begin    
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
=end   
    # Optionals - Audience, TODO: better to lookup labels on the fly!
    if review.audience
      case review.audience.downcase
      when 'barn' || 'ungdom' || 'barn/ungdom' || 'juvenile'
        insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/juvenile"))
      else
        insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/adult"))
      end
    end

    query = QUERY.insert_data(insert_statements).graph(REVIEWGRAPH)
    puts "#{query}"
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
    # update review here
    # first use api_key parameter to fetch source
    puts "hey: #{params.inspect}" 
    source = find_source_by_apikey(params[:api_key])
    return "Invalid api_key" unless source
    
    work   = self.find_reviews(params).first
    review = work.reviews.first 
    # handle modified variables from given params
    #puts "params before:\n #{params}"
    unwanted_params = ['uri', 'api_key', 'route_info', 'method', 'path']
#    mapped_params   = {
#                      'title'    => 'review_title', 
#                      'teaser'   => 'review_abstract', 
#                      'text'     => 'review_text', 
#                      'reviewer' => 'reviewer', 
#                      'audience' => 'review_audience'
#                      }
    unwanted_params.each {|d| params.delete(d)}
#    params.keys.each     {|k| params[ mapped_params[k] ] = params.delete(k) if mapped_params[k] }
    
    #puts "params after:\n #{params}"
    
    puts "before update:\n#{work}"
    # update review with new params
    params.each{|k,v| review[k] = v}
    #new = params.to_struct "Review"
    # set modified time
    review.modified = Time.now.xmlschema
    review.teaser   = clean_text(review.teaser)
    review.text     = clean_text(review.text)
    puts "after update:\n#{work}"
    
    # SPARQL UPDATE
    deletequery = QUERY.delete([review.uri, :p, :o]).graph(REVIEWGRAPH)
    deletequery.where([review.uri, :p, :o])
    # MINUS not working properly until virtuoso 6.1.6!
    #deletequery.minus([review.review_id, RDF::DC.created, :o])
    #deletequery.minus([review.review_id, RDF::DC.issued, :o])
    deletequery.filter("?p != <#{RDF::DC.created.to_s}>")
    deletequery.filter("?p != <#{RDF::DC.issued.to_s}>")
    
    puts "deletequery:\n #{deletequery}"
    result = REPO.delete(deletequery)
    puts "delete result:\n #{result}"
    
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
        
    # Optionals - audience, FIX: better to lookup labels on the fly!
    if review.audience
      case review.audience.downcase
      when 'barn' || 'ungdom' || 'barn/ungdom' || 'juvenile'
        insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/juvenile"))
      else
        insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/adult"))
      end
    end
    
    insertquery = QUERY.insert_data(insert_statements).graph(REVIEWGRAPH)
    puts "insertquery:\n #{insertquery}"
    result = REPO.insert_data(insertquery)
    puts "insert result:\n #{result}"    
    work
  end
  
  def delete(params = {})
    # delete review here
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
    result    = REPO.delete(query)
  end

  def clean_text(text)
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
    Struct.new(name, *keys).new(*values)
  end
end

