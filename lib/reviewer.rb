class Review
  def find_reviewer(params)
    # looks in apigraph for reviewer by either reviewer's foaf:name or reviewer account's foaf:accountName
    query = QUERY.select(:reviewer_id, :reviewer_name, :accountName, :reviewer_workplace).from(APIGRAPH)
    query.where([:reviewer_id, RDF.type, RDF::FOAF.Person],
    # reviewer by foaf name
      [:reviewer_id, RDF::FOAF.name, :reviewer_name],
    # reviewer by accountname
      [:reviewer_id, RDF::FOAF.account, :useraccount],
      [:useraccount, RDF::FOAF.accountName, :accountName])
    # reviewer workplace
    query.optional(
      [:reviewer_id, RDF::ORG.memberOf, :workplace_id],
      [:workplace_id, RDF::SKOS.prefLabel, :reviewer_workplace])      
    # do filter on reviewer id|name|nick
    query.filter("regex(?reviewer_id, \"#{params}\", \"i\") || 
                  regex(?reviewer_name, \"#{params}\", \"i\") || 
                  regex(?accountName, \"#{params}\", \"i\")")
                  
    puts "#{query}" if ENV['RACK_ENV'] == 'development'
    solutions = REPO.select(query)
    #puts solutions.inspect
    return nil if solutions.empty?
    reviewer = solutions.first
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
    puts "create reviewer query: #{query}" if ENV['RACK_ENV'] == 'development'
    result = REPO.insert_data(query)
    puts "create reviewer result: #{result}" if ENV['RACK_ENV'] == 'development'
    reviewer = {:reviewer_id => reviewer_id, :reviewer_name => "#{reviewer}", :accountName => "#{account_name}", :reviewer_workplace => nil}
  end  
end
