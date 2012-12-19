#encoding: utf-8
require 'rdf/n3'
# Structs are simple classes with fixed sequence of instance variables
Work = Struct.new(:title, :isbn, :book_id, :work_id, :author, :cover_url, :reviews)
Review = Struct.new(:uri, :title, :teaser, :text, :source, :reviewer, :audience, :created, :issued, :modified) do

  # main method to find reviews, GET /api/review
  # params: uri, isbn, title, author, reviewer, work
  def find_reviews(params = {})
    selects     = [:uri, :book_id, :work_id, :book_title, :created, :issued, :modified, :review_title, :review_abstract, :cover_url, :review_source, :review_audience, :reviewer_name, :reviewer_nick]
    
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
      isbn          = "#{params[:isbn].strip.gsub(/[^0-9]/, '')}"
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
      [:useraccount, RDF::FOAF.accountName, :reviewer_nick, :context => APIGRAPH]
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
    
    query.filter("regex(?reviewer_name, \"#{api[:reviewer]}\", \"i\")") if params[:reviewer]
    query.filter("regex(?reviewer_nick, \"#{api[:reviewer]}\", \"i\")") if params[:reviewer]
    
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
  
  def find_reviewer
  end
  
  def autoincrement_source(source = nil)
    # This method uses Virtuoso's internal sequence function to generate unique ID from api_key mapped to source
    # sql:sequence_next("GRAPH_IDENTIFIER") => returns next sequence from GRAPH_IDENTIFIER
    # sql:sequence_set("GRAPH_IDENTIFIER", new_sequence_number, ignorelower_boolean) => sets sequence number
    # get unique sequential id by CONSTRUCTing an id based on source URI
    if source
      query = <<-EOQ
      PREFIX rev: <http://purl.org/stuff/rev#>
      CONSTRUCT { `iri(bif:CONCAT("http://data.deichman.no/bookreviews/", bif:REPLACE(str(?source), "http://data.deichman.no/sources/", ""), "/id_", str(bif:sequence_next ('#{source}', 1, ?source)) ) )` a rev:Review } 
      WHERE { <#{source}> a foaf:Document ; foaf:name ?name . ?source a foaf:Document ; foaf:name ?name } ORDER BY(?source) LIMIT 1 
  EOQ
      # nb: to reset count use sequence_set instead, with an iri f.ex. like this:
      # `iri(bif:CONCAT("http://data.deichman.no/bookreviews/", bif:REPLACE(str(?source), "http://data.deichman.no/sources/", ""), "/id_", str(bif:sequence_next ('#{source}', 0, 0)) ) )`
      puts "#{query}"
      solutions = REPO.construct(query)
      
      return nil if solutions.empty?
      review_id = solutions.first[:s]
    end
  end
  
  def create(params)
    # create new review here
    # first use api_key parameter to fetch source
    source = find_source_by_apikey(params[:api_key])
    return "Invalid api_key" unless source
    
    # find work based on isbn
    isbn = params[:isbn].strip.gsub(/[^0-9]/, '')

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
      uri = autoincrement_source(source)
      return "Invalid URI" unless uri
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
          params[:teaser],
          params[:text],
          source,
          params[:reviewer] ? params[:reviewer] : nil,
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
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.subject, RDF::URI(work.isbn))
    #insert_statements << RDF::Statement.new(review.uri, RDF::DEICHMAN.basedOnManifestation, RDF::URI(work.book_id))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.created, RDF::Literal(review.created, :datatype => RDF::XSD.dateTime))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.issued, RDF::Literal(review.issued, :datatype => RDF::XSD.dateTime))
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
   
    # Optionals - Audience, TODO: better to lookup labels on the fly!
    if review.audience
      case review.audience.downcase
      when 'voksen' || 'adult'
        insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/adult"))
      when 'barn' || 'ungdom' || 'juvenile'
        insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/juvenile"))
      else
        # insert nothing
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
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.subject, RDF::URI(work.work_id))
    insert_statements << RDF::Statement.new(review.uri, RDF::DEICHMAN.basedOnManifestation, RDF::URI(work.book_id))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.modified, RDF::Literal(Time.now.xmlschema, :datatype => RDF::XSD.dateTime))

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
      when 'voksen' || 'adult'
        insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/adult"))
      when 'barn' || 'ungdom' || 'juvenile'
        insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/juvenile"))
      else
        #
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
    query = QUERY.delete([uri, :p, :o]).where([uri, RDF::DC.source, source], [uri, :p, :o]).graph(REVIEWGRAPH)
    #puts "#{query}"
    result = REPO.delete(query)
    # and delete hasReview reference from work
    query = QUERY.delete([:work, RDF::REV.hasReview, uri])
    query.where([:work, RDF::REV.hasReview, uri]).graph(BOOKGRAPH)
    result    = REPO.delete(query)
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

