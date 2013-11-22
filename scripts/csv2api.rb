#!/usr/bin/env ruby 
# encoding: UTF-8

if RUBY_VERSION <= "1.8.7" then $KCODE = 'u' end #needed for string conversion in ruby 1.8.7
require 'rubygems'
require 'csv'
require 'json'
require 'httpclient'

# This script reads a CSV with book recommendations and POSTs to the recommendations API
# required parameters are: 
# -a (url to API) 
# -k (api_key)  

# Important: first row are headers and must correspond to API parameters:
# - isbn
# - title
# - teaser
# - text
# - audience (optional)
# - reviewer (optional)
# - reviewer_name (optional)


def usage(s)
    $stderr.puts(s)
    $stderr.puts("Usage: \n")
    $stderr.puts("#{File.basename($0)} -i input_file.csv -a api_url\n")
    $stderr.puts("  -i input_file \(csv\)\n")
    $stderr.puts("  -a url to API \n")
    $stderr.puts("  -k API key \n")
    $stderr.puts("  -p (to publish directly) \n")
    $stderr.puts("  -d (to output debug info)\n")
    $stderr.puts("  -t (to test only, don't run actual import)\n")
    exit(2)
end

loop { case ARGV[0]
    when '-i' then  ARGV.shift; $input_file  = ARGV.shift
    when '-a' then  ARGV.shift; $api_url     = ARGV.shift
    when '-k' then  ARGV.shift; $api_key     = ARGV.shift
    when '-p' then  ARGV.shift; $publish = true
    when '-d' then  ARGV.shift; $debug = true
    when '-t' then  ARGV.shift; $test = true    
    when /^-/ then  usage("Unknown option: #{ARGV[0].inspect}")
    else 
      if $input_file.nil? then usage("Missing argument!\n") end
    break
end; }

reviews = {}

# defaults
$api_url = "http://localhost:9393/api/reviews" unless $api_url
$api_key = "test" unless $api_key


csv_data = CSV.read $input_file
headers = csv_data.shift.map {|i| i.to_s }
string_data = csv_data.map {|row| row.map {|cell| cell.to_s } }
reviews = string_data.map {|row| Hash[*headers.zip(row).flatten] }
puts reviews.inspect if $test

# Run POSTs unless test parameter given
unless $test
  http = HTTPClient.new
  reviews.each do | review|
    review[:api_key] = "#{$api_key}"
    review[:published] = true if $publish
    res = http.post $api_url, review.to_json
    puts res.body if $debug
  end
end
