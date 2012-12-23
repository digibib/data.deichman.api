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
end
