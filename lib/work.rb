#encoding: utf-8
Work = Struct.new(:uri, :isbn, :title, :manifestation, :author_id, :author, :cover_url, :reviews)

class Work
  # under construction
  def find(params)
    selects     = [:uri, :isbn, :title, :manifestation, :author, :author_id, :cover_url]
    api = Hashie::Mash.new(:uri => :uri, :isbn => :isbn, :author => :author, :author_id => :author_id, :title => :title)
    params[:isbn] = String.new.sanitize_isbn(params[:isbn]) if params[:isbn]
    api.merge!(params)
    # remove variable from selects array if variable given as param
    selects.delete_if {|s| params[s]}
    
    query = QUERY.select(*selects).from(BOOKGRAPH)
    query.where(
      [:uri, RDF.type, RDF::FABIO.Work], 
      [:manifestation, RDF::BIBO.isbn, api[:isbn]],
      [:uri, RDF::DC.creator, :author_id],
      [:author_id, RDF::FOAF.name, :author],
      [:uri, RDF::DC.title, :title],
      [:uri, RDF::BIBO.isbn, api[:isbn]],
      [:uri, RDF::FABIO.hasManifestation, :manifestation]
      )
    query.optional([:manifestation, RDF::FOAF.depiction, :cover_url])
    query.limit(10)
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    return nil if solutions.empty?
    works = []
    solutions.each do |s|
      s[:isbn] = params[:isbn] if params[:isbn] 
      works << s.to_hash.to_struct("Work")
    end
    works
  end
end
