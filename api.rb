#encoding: utf-8
$stdout.sync = true

require "bundler/setup"
require "grape"
require "rdf/virtuoso"
require "./vocabularies.rb"

repository = YAML::load(File.open("config/repository.yml"))
REPO = RDF::Virtuoso::Repository.new(
              repository["sparql_endpoint"],
              :update_uri => repository["sparul_endpoint"],
              :username => repository["username"],
              :password => repository["password"],
              :auth_method => repository["auth_method"])

QUERY       = RDF::Virtuoso::Query
REVIEWGRAPH = RDF::URI('http://data.deichman.no/reviews')
BOOKGRAPH   = RDF::URI('http://data.deichman.no/books')

class Review
  attr_accessor :review_id, :review_title, :review_abstract, :review_text, :review_source, :review_reviewer, :review_audience
  attr_reader   :book_id, :book_title, :isbn, :work_id
                
  def initialize
  end

  def find(params = {})
    # find reviews by uri, isbn, title/author
    
    selects = [:uri, :isbn, :book_title, :issued, :review_title, :review_abstract, :review_text, :review_source, :reviewer, :review_publisher]
    
    if params.has_key?(:uri)
      begin 
        selects.delete(:uri)
        uri = URI::parse(params[:uri])
        uri = RDF::URI(uri)
        isbn = :isbn
      rescue URI::InvalidURIError
        return "Invalid URI"
      end
    elsif params.has_key?(:isbn)
      selects.delete(:isbn)
      uri           = :uri
      isbn          = "#{params[:isbn].strip.gsub(/[^0-9]/, '')}"
    else
      author_search = params[:author] ? params[:author].gsub(/[[:punct:]]/, '').split(" ") : nil
      title_search  = params[:title] ? params[:title].gsub(/[[:punct:]]/, '').split(" ") : nil
      uri           = :uri
      isbn          = :isbn
    end

    query = QUERY.select(*selects)
    query.group_digest(:author, ', ', 1000, 1)
    query.distinct.where(
      [uri, RDF.type, RDF::REV.Review, :context => REVIEWGRAPH],
      [uri, RDF::DEICHMAN.basedOnManifestation, :book, :context => REVIEWGRAPH],
      [uri, RDF::DC.issued, :issued, :context => REVIEWGRAPH],
      [:book, RDF::BIBO.isbn, isbn, :context => BOOKGRAPH],
      [:book, RDF::DC.title, :book_title, :context => BOOKGRAPH],
      [:book, RDF::DC.creator, :author_id, :context => BOOKGRAPH],
      [:author_id, RDF::FOAF.name, :author, :context => BOOKGRAPH]    # should we really require foaf:name on book author?
      )
    query.optional([uri, RDF::REV.title, :review_title, :context => REVIEWGRAPH])
    query.optional([uri, RDF::DC.abstract, :review_abstract, :context => REVIEWGRAPH])
    query.optional([uri, RDF::REV.text, :review_text, :context => REVIEWGRAPH])
    query.optional([uri, RDF::DC.source, :review_source, :context => REVIEWGRAPH])
    query.optional([uri, RDF::REV.reviewer, :reviewer_id, :context => REVIEWGRAPH],
                   [:reviewer_id, RDF::FOAF.name, :reviewer, :context => REVIEWGRAPH])
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
    reviews = []
    solutions.each do |solution|
      s = {}
      solution.each_binding { |name, value| s[name] = value.to_s }
      reviews.push(s)
    end
    reviews
  end  
  
  def find_source_by_apikey(api_key)
    # make query to http://data.deichman.no/reviews/sources/apikeys
    case api_key
    when 'deichmanapikey'
      source = 'http://data.deichman.no/sources/dummy'
    else
      source = 'http://data.deichman.no/sources/dummy'
    end
  end
  
  def autoincrement_source
    # This method uses Virtuoso's internal sequence function to generate unique ID from api_key mapped to source
    # sql:sequence_next("GRAPH_IDENTIFIER") => returns next sequence from GRAPH_IDENTIFIER
    # sql:sequence_set("GRAPH_IDENTIFIER", new_sequence_number, ignorelower_boolean) => sets sequence number
    # get unique sequential id by CONSTRUCTing an id based on source URI
    if self.review_source
      query = <<-EOQ
PREFIX rev: <http://purl.org/stuff/rev#>
CONSTRUCT { `iri(bif:CONCAT("http://data.deichman.no/bookreviews/", bif:REPLACE(str(?source), "http://data.deichman.no/sources/", ""), "/id_", str(bif:sequence_next ('#{self.review_source}', 1, ?source)) ) )` a rev:Review } 
  WHERE { <#{self.review_source}> a rdfs:Resource ; rdfs:label ?label . ?source a rdfs:Resource ; rdfs:label ?label } ORDER BY(?source) LIMIT 1 
  EOQ
      # nb: to reset count use sequence_set instead, with an iri f.ex. like this:
      # `iri(bif:CONCAT("http://data.deichman.no/bookreviews/", bif:REPLACE(str(?source), "http://data.deichman.no/sources/", ""), "/id_", str(bif:sequence_next ('#{self.review_source}', 0, 0)) ) )`

      solutions = REPO.construct(query)
      review_id = solutions.first[:s]
    end
  end
  
  def create(params)
    # create new review here
    # first use api_key parameter to fetch source
    @review_source = find_source_by_apikey(params[:api_key])
    @isbn          = params[:isbn].strip.gsub(/[^0-9]/, '')
    
    # lookup book based on isbn
    query = QUERY.select(:book_id, :book_title, :work_id)
    query.from(BOOKGRAPH)
    query.where(
      [:book_id, RDF::BIBO.isbn, "#{@isbn}"],
      [:book_id, RDF.type, RDF::BIBO.Document],
      [:book_id, RDF::DC.title, :book_title],
      [:work_id, RDF::FABIO.hasManifestation, :book_id]
      )
    puts "#{query}"
    solutions = REPO.select(query)
    
    # populate review attributes
    unless solutions.empty?
      @book_id          = solutions.first[:book_id]
      @book_title       = solutions.first[:book_title]
      @work_id          = solutions.first[:work_id]
      @review_id        = autoincrement_source
      @review_title     = params[:title]
      @review_abstract  = params[:teaser]
      @review_text      = params[:text]
      @review_reviewer  = params[:reviewer] if params[:reviewer] 
      @review_audience  = params[:audience] if params[:audience]
    else
      return nil # break out if isbn returns no hits
    end    
    
    insert_statements = []
    insert_statements << RDF::Statement.new(self.review_id, RDF.type, RDF::REV.Review)
    insert_statements << RDF::Statement.new(self.review_id, RDF::DC.source, RDF::URI(self.review_source))
    insert_statements << RDF::Statement.new(self.review_id, RDF::REV.title, RDF::Literal(self.review_title))
    insert_statements << RDF::Statement.new(self.review_id, RDF::DC.abstract, RDF::Literal(self.review_abstract))
    insert_statements << RDF::Statement.new(self.review_id, RDF::REV.text, RDF::Literal(self.review_text))
    insert_statements << RDF::Statement.new(self.review_id, RDF::DC.subject, RDF::URI(self.work_id))
    insert_statements << RDF::Statement.new(self.review_id, RDF::DEICHMAN.basedOnManifestation, RDF::URI(self.book_id))
    insert_statements << RDF::Statement.new(self.review_id, RDF::DC.created, RDF::Literal(Time.now.xmlschema, :datatype => RDF::XSD.dateTime))
    insert_statements << RDF::Statement.new(self.review_id, RDF::DC.issued, RDF::Literal(Time.now.xmlschema, :datatype => RDF::XSD.dateTime))
    
    # optionals
    # need lookup in rdf store before these can be used!
    #insert_statements << RDF::Statement.new(self.review_id, RDF::REV.reviewer, RDF::URI(self.review_reviewer)) if self.review_reviewer
    #insert_statements << RDF::Statement.new(self.review_id, RDF::DC.audience, RDF::URI(self.review_audience)) if self.review_audience
        
    query = QUERY.insert_data(insert_statements).graph(REVIEWGRAPH)
    puts query
    result = REPO.insert_data(query)
    
  end
  
  def update(params = {})
    # update review here
  end
  
  def delete(params = {})
    # delete review here
    # first use api_key parameter to fetch source

    @review_source = find_source_by_apikey(params[:api_key])
    source = RDF::URI(@review_source)
    uri    = RDF::URI(params[:uri])
    
    # find review
    review = find(params)

    # then delete review, but only if source matches
    query = QUERY.delete([uri, :p, :o]).where([uri, RDF::DC.source, source], [uri, :p, :o]).graph(REVIEWGRAPH)
    puts query
    
    result = REPO.delete(query)
  end
  
  # methods to export class instance variables to hash
  # necessary to export JSON
  def to_hash
      hash = {}
      self.instance_variables.each do |var|
          hash[var.to_s.delete("@")] = self.instance_variable_get var
      end
      hash
  end
  # method to import JSON to class instant variables
  # currently not used
  def from_json! string
      JSON.load(string).each do |var, val|
          self.instance_variable_set var, val
      end
  end
end

class API < Grape::API
  prefix 'api'
  format :json
  default_format :json

  resource :reviews do
    desc "returns reviews"
      params do
        optional :uri,    type: String, desc: "URI of review"
        optional :isbn,   type: String, desc: "ISBN of reviewed book"
        optional :author, type: String, desc: "Book author"
        optional :title,  type: String, desc: "Book title"
      end
    get "/" do
    content_type 'json'
      reviews = Review.new.find(params)
      throw :error, :status => 400, :message => "\"#{params[:uri]}\" is not a valid URI" if reviews == "Invalid URI"
      throw :error, :status => 200, :message => "no reviews found" if reviews.empty?
      header['Content-Type'] = 'application/json; charset=utf-8'
      { :request => params, :reviews => reviews }
    end

    desc "creates a review"
      params do
        requires :api_key,  type: String, desc: "Authorization Key"
        requires :title,    type: String, desc: "Title of review"
        requires :teaser,   type: String, desc: "Abstract of review"
        requires :text,     type: String, desc: "Text of review"
        requires :isbn,     type: String, desc: "ISBN of reviewed book"
        optional :reviewer, type: String, desc: "Name of reviewer"
        optional :audience, type: String, desc: "Audience of review"
        #optional :source, type: String, desc: "Source of review"
      end
    post "/" do
      content_type 'json'
      review = Review.new
      result = review.create(params)
           
      throw :error, :status => 400, :message => "Sorry, #{params[:isbn]} matches no known book in our base" unless result
      header['Content-Type'] = 'application/json; charset=utf-8' 
      {:request => params, :result => result, :review => review.to_hash }
    end

    desc "updates a review"
    put "/" do
      "Hello world"
    end

    desc "deletes a review"
      params do
        requires :api_key, type: String, desc: "Authorization Key"
        requires :uri,     type: String, desc: "URI of review"
      end    
    delete "/" do
      content_type 'json'
      # is it in the base?
      review = Review.new.find(params)
      throw :error, :status => 400, :message => "Sorry, \"#{params[:uri]}\" matches no review in our base" if review.empty?
      # yes, then delete it!
      result = Review.new.delete(params)
      throw :error, :status => 400, :message => "Sorry, unable to delete review #{params[:uri]} ..." if result =~ /nothing to do/
      header['Content-Type'] = 'application/json; charset=utf-8' 
      {:request => params, :review => review, :result => result }
    end
  end
end
