#encoding: utf-8
require "sanitize"
# RemoveAccents version 1.0.3 (c) 2008-2009 Solutions Informatiques Techniconseils inc.
# 
# This module adds 2 methods to the string class. 
# Up-to-date version and documentation available at:
#
# http://www.techniconseils.ca/en/scripts-remove-accents-ruby.php
#
# This script is available under the following license :
# Creative Commons Attribution-Share Alike 2.5.
#
# See full license and details at :
# http://creativecommons.org/licenses/by-sa/2.5/ca/
#
class String
  # The extended characters map used by removeaccents. The accented characters 
  # are coded here using their numerical equivalent to sidestep encoding issues.
  # These correspond to ISO-8859-1 encoding.
  CHAR_MAPPING = {
    'E' => [200,201,202,203],
    'e' => [232,233,234,235],
    'A' => [192,193,194,195],
    'a' => [224,225,226,227],
    'C' => [199],
    'c' => [231],
    'O' => [210,211,212,213],
    'o' => [242,243,244,245],
    'I' => [204,205,206,207],
    'i' => [236,237,238,239],
    'U' => [217,218,219,220],
    'u' => [249,250,251,252],
    'N' => [209],
    'n' => [241],
    'Y' => [221],
    'y' => [253,255],
    'Ae' => [196,198],
    'ae' => [228,230],
    'Oe' => [214,216],
    'oe' => [246,248],
    'Aa' => [197],
    'aa' => [229]
  }
  
  # Replaces characters in string. Uses String::CHAR_MAPPING as the source map.
  def replacecharacters    
    str = String.new(self)
    String::CHAR_MAPPING.each {|ascii,nonascii|
      packed = nonascii.pack('U*')
      rxp = Regexp.new("[#{packed}]", nil)
      str.gsub!(rxp, ascii)
    }
    str
  end
  
  # Convert a string to a format suitable for a URL without ever using escaped characters.
  # It calls strip, removeaccents, downcase (optional) then removes the spaces (optional)
  # and finally removes any characters matching the default regexp (/[^-_A-Za-z0-9]/).
  #
  # Options
  #
  # * :downcase => call downcase on the string (defaults to false)
  # * :convert_spaces => Convert space to underscore (defaults to true)
  # * :regexp => The regexp matching characters that will be converting to an empty string (defaults to /[^-_A-Za-z0-9]/)
  def urlize(options = {})
    downcase = options[:downcase] || true
    convert_spaces = options[:convert_spaces] || true
    regexp = options[:regexp] || /[^-_A-Za-z0-9]/
    
    str = self.strip.replacecharacters
    str.downcase! if downcase
    str.gsub!(/\ /,'_') if convert_spaces
    str.gsub(regexp, '')
  end

  def to_class
    Object.const_get(self)
  end
  
  ## Class methods
  
  # split values in param separated with comma or slash or pipe and return array
  def self.split_param(param)
    params = param.downcase.gsub(/\s+/, '').split(/,|\/|\|/)
  end

  # this method cleans html tags and other presentation awkwardnesses  
  def self.clean_text(text)
    # first remove all but whitelisted html elements
    sanitized = Sanitize.clean(text, 
      :elements => %w[p pre small em i strong strike b blockquote q cite code br h1 h2 h3 h4 h5 h6],
      :attributes => {'span' => ['class']},
      :remove_contents => %w[style script iframe])
    # then strip newlines, tabs carriage returns and return pretty text
    result = sanitized.gsub(/\s+/, ' ').squeeze(' ')
  end  
  
  # removes any char not accepted in ISBN
  def self.sanitize_isbn(isbn)
    isbn.strip.gsub(/[^0-9xX]/, '')
  end

end

# patched Struct and Hash classes to allow easy conversion to/from JSON and Hash
class Struct
  def to_map
    # this method returns Hash map of Struct
    map = Hash.new
    self.members.each { |m| map[m] = self[m] }
    # strip out empty struct values and nils
    map.reject! {|k,v| v.strip.empty? if v.is_a?(String) && v.respond_to?('empty?') ; v.nil? }
    map
  end
  def to_json(*a)
    to_map.to_json(*a)
  end
end

class Hash
  # transforms hash to struct
  def to_struct(name)
    # This method returns struct object "name" from hash object
    unless defined?(name)
      Struct.new(name, *keys).new(*values)
    else
      # constantize to struct class and populate
      struct = name.to_class.new
      struct.members.each {|n| struct[n] = self[n] }
      struct  
    end 
  end
  
  # remove empty params from params Hash
  def remove_empty_params!
    self.delete_if {|k,v| v.respond_to?(:empty?) && v.empty? }
  end
end

# monkey-patch Virtuoso gem for pretty printing to logs 
module RDF::Virtuoso
  class Query
    def pp
      self.to_s.gsub(/(SELECT|FROM|WHERE|GRAPH|FILTER)/,"\n"+'\1').gsub(/(\s\.\s|WHERE\s{\s|})(?!})/, '\1'+"\n")
    end
  end
end
