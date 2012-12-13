#encoding: utf-8
require 'rdf/n3'
# Structs are simple classes with fixed sequence of instance variables
Work = Struct.new(:title, :isbn, :book_id, :work_id, :author, :cover_url, :reviews)
Review = Struct.new(:uri, :title, :teaser, :text, :source, :reviewer, :audience, :created, :issued, :modified) do

  # main method to find reviews, GET /api/review
  # params: uri, isbn, title/author
  def find_reviews(params = {})
    
    selects = [:uri, :book_id, :work_id, :book_title, :created, :issued, :modified, :review_title, :review_abstract, :cover_url, :review_source, :reviewer, :review_publisher, :review_audience]
    
    if params.has_key?(:uri)
      begin 
        selects.delete(:uri)
        uri = URI::parse(params[:uri])
        uri = RDF::URI(uri)
        isbn = :isbn
        #solutions = find_reviews_by_uri(params[:uri], selects)
      rescue URI::InvalidURIError
        return "Invalid URI"
      end
    elsif params.has_key?(:isbn)
      #selects.delete(:isbn)
      uri           = :uri
      isbn          = "#{params[:isbn].strip.gsub(/[^0-9]/, '')}"
    else
      author_search = params[:author] ? params[:author].gsub(/[[:punct:]]/, '').split(" ") : nil
      title_search  = params[:title] ? params[:title].gsub(/[[:punct:]]/, '').split(" ") : nil
      uri           = :uri
      isbn          = :isbn
    end

    # query RDF store for work and reviews
    query = QUERY.select(*selects)
    query.group_digest(:author, ', ', 1000, 1)
    query.group_digest(:isbn, ', ', 1000, 1) if isbn == :isbn
    query.distinct.where(
      [uri, RDF.type, RDF::REV.Review, :context => REVIEWGRAPH],
      [uri, RDF::DEICHMAN.basedOnManifestation, :book_id, :context => REVIEWGRAPH],
      [uri, RDF::DC.created, :created, :context => REVIEWGRAPH],
      [uri, RDF::DC.issued, :issued, :context => REVIEWGRAPH],
      [uri, RDF::DC.modified, :modified, :context => REVIEWGRAPH],
      [uri, RDF::REV.title, :review_title, :context => REVIEWGRAPH],
      [uri, RDF::DC.abstract, :review_abstract, :context => REVIEWGRAPH],
      [:book_id, RDF::BIBO.isbn, isbn, :context => BOOKGRAPH],
      [:book_id, RDF::DC.title, :book_title, :context => BOOKGRAPH],
      [:book_id, RDF::DC.creator, :author_id, :context => BOOKGRAPH],
      [:work_id, RDF::FABIO.hasManifestation, :book_id, :context => BOOKGRAPH],
      [:author_id, RDF::FOAF.name, :author, :context => BOOKGRAPH]    # should we really require foaf:name on book author?
      )
    # optional attributes
    # NB! these optionals adds extra ~2 sec to query
    query.optional([:book_id, RDF::FOAF.depiction, :cover_url, :context => BOOKGRAPH])
    
    #query.optional([uri, RDF::REV.text, :review_text, :context => REVIEWGRAPH]) # moved to separate query due to some very long blobs

    query.optional([uri, RDF::DC.source, :review_source_id, :context => REVIEWGRAPH],
      [:review_source_id, RDF::RDFS.label, :review_source, :context => BOOKGRAPH])
    query.optional([uri, RDF::REV.reviewer, :reviewer_id, :context => REVIEWGRAPH],
      [:reviewer_id, RDF::FOAF.name, :reviewer, :context => REVIEWGRAPH])
    query.optional([uri, RDF::DC.audience, :review_audience_id, :context => REVIEWGRAPH],
      [:review_audience_id, RDF::RDFS.label, :review_audience, :context => BOOKGRAPH])                   
    query.optional([uri, RDF::DC.publisher, :publisher_id, :context => REVIEWGRAPH],
      [:publisher_id, RDF::FOAF.name, :review_publisher, :context => REVIEWGRAPH])

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
    query.limit(50)

    puts query
    solutions = REPO.select(query)
    
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
          
          review = Review.new(
                          solution[:uri] ? solution[:uri].to_s : uri,
                          solution[:review_title].to_s,
                          solution[:review_abstract].to_s,
                          #solution[:review_text].to_s,
                          review_text,
                          solution[:review_source].to_s,
                          solution[:reviewer].to_s,
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
  
  def find_reviews_by_uri(params, selects)

  end
  
  def find_source_by_apikey(api_key)
    # fetch source by api key in protected graph
    # each source needs three statements: 
    # <source> a rdfs:Resource ;
    #          rdfs:label "Label" ;
    #          deichman:apikey "apikey" .    
    query = QUERY.select(:source).from(APIGRAPH)
    query.where(
      [:source, RDF.type, RDF::RDFS.Resource], 
      [:source, RDF::RDFS.label, :label],
      [:source, RDF::DEICHMAN.apikey, "#{api_key}"])
    query.limit(1)
    #puts query
    solutions = REPO.select(query)
    return nil if solutions.empty?
    source = solutions.first[:source]
  end
  
  def autoincrement_source(source = nil)
    # This method uses Virtuoso's internal sequence function to generate unique ID from api_key mapped to source
    # sql:sequence_next("GRAPH_IDENTIFIER") => returns next sequence from GRAPH_IDENTIFIER
    # sql:sequence_set("GRAPH_IDENTIFIER", new_sequence_number, ignorelower_boolean) => sets sequence number
    # get unique sequential id by CONSTRUCTing an id based on source URI
    if source
      query = <<-EOQ
  PREFIX rev: <http://purl.org/stuff/rev#>
  CONSTRUCT { `iri(bif:CONCAT("http://data.deichman.no/bookreviews/", bif:REPLACE(str(?source), "http://data.deichman.no/sources/", ""), "/id_", str(bif:sequence_next ('#{review_source}', 1, ?source)) ) )` a rev:Review } 
  WHERE { <#{source}> a rdfs:Resource ; rdfs:label ?label . ?source a rdfs:Resource ; rdfs:label ?label } ORDER BY(?source) LIMIT 1 
  EOQ
      # nb: to reset count use sequence_set instead, with an iri f.ex. like this:
      # `iri(bif:CONCAT("http://data.deichman.no/bookreviews/", bif:REPLACE(str(?source), "http://data.deichman.no/sources/", ""), "/id_", str(bif:sequence_next ('#{self.review_source}', 0, 0)) ) )`
      #puts "#{query}"
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
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.subject, RDF::URI(work.work_id))
    insert_statements << RDF::Statement.new(review.uri, RDF::DEICHMAN.basedOnManifestation, RDF::URI(work.book_id))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.created, RDF::Literal(review.created, :datatype => RDF::XSD.dateTime))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.issued, RDF::Literal(review.issued, :datatype => RDF::XSD.dateTime))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.modified, RDF::Literal(review.modified, :datatype => RDF::XSD.dateTime))

    # optionals
    # need lookup in rdf store before these can be used!
    #insert_statements << RDF::Statement.new(work.reviews.review_id, RDF::REV.reviewer, RDF::URI(self.review_reviewer)) if self.review_reviewer
    # audience, FIX: better to lookup labels on the fly!
    if review.audience
      case review.audience.downcase
      when 'voksen'
        insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/adult"))
      when 'barn/ungdom'
        insert_statements << RDF::Statement.new(review.uri, RDF::DC.audience, RDF::URI("http://data.deichman.no/audience/juvenile"))
      else
        # insert nothing
      end
    end

    query = QUERY.insert_data(insert_statements).graph(REVIEWGRAPH)
    #puts "#{query}"
    result = REPO.insert_data(query)
    
    # also insert hasReview property on work
    hasreview_statement  = []
    hasreview_statement << RDF::Statement.new(RDF::URI(work.work_id), RDF::FABIO.hasReview, review.uri)
    workquery            = QUERY.insert_data(hasreview_statement).graph(BOOKGRAPH)
    result               = REPO.insert_data(workquery)
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
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.abstract, RDF::Literal(review.abstract))
    insert_statements << RDF::Statement.new(review.uri, RDF::REV.text, RDF::Literal(review.text))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.subject, RDF::URI(work.work_id))
    insert_statements << RDF::Statement.new(review.uri, RDF::DEICHMAN.basedOnManifestation, RDF::URI(work.book_id))
    insert_statements << RDF::Statement.new(review.uri, RDF::DC.modified, RDF::Literal(Time.now.xmlschema, :datatype => RDF::XSD.dateTime))
    
    # optionals
    # need lookup in rdf store before these can be used!
    #insert_statements << RDF::Statement.new(review.review_id, RDF::REV.reviewer, RDF::URI(review.review_reviewer)) if review.review_reviewer
    # audience, FIX: better to lookup labels on the fly!
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
    hasReview_query = QUERY.delete([:work, RDF::FABIO.hasReview, uri])
    hasReview_query.where([:work, RDF.type, RDF::FABIO.Work],[:work, RDF::FABIO.hasReview, uri]).graph(BOOKGRAPH)
    result    = REPO.delete(hasReview_query)
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

