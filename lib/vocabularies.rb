# encoding: UTF-8
require 'rdf'

module RDF
  class BIBO < RDF::Vocabulary("http://purl.org/ontology/bibo/");end
  class XFOAF < RDF::Vocabulary("http://www.foafrealm.org/xfoaf/0.1/")
    property :name
  end
  class LEXVO < RDF::Vocabulary("http://lexvo.org/ontology#")
    property :name
  end
  class DEICHMAN < RDF::Vocabulary("http://data.deichman.no/");end
  class DEICH < RDF::Vocabulary("http://data.deichman.no/ontology#")
    property :name
  end
  class REV < RDF::Vocabulary("http://purl.org/stuff/rev#");end
  class DBO < RDF::Vocabulary("http://dbpedia.org/ontology/");end
  class FABIO < RDF::Vocabulary("http://purl.org/spar/fabio/");end
  class FRBR < RDF::Vocabulary("http://purl.org/vocab/frbr/core#");end
  class RDA < RDF::Vocabulary("http://rdvocab.info/Elements/");end
  class GEONAMES < RDF::Vocabulary("http://www.geonames.org/ontology#")
    property :name
  end
  class YAGO < RDF::Vocabulary("http://dbpedia.org/class/yago/");end
  class CTAG < RDF::Vocabulary("http://commontag.org/ns#");end
  class RADATANA < RDF::Vocabulary("http://def.bibsys.no/xmlns/radatana/1.0#");end
  class ACC < RDF::Vocabulary("http://purl.org/NET/acc#");end
  class ORG < RDF::Vocabulary("http://www.w3.org/ns/org#");end
  class IFACE < RDF::Vocabulary("http://www.multimedian.nl/projects/n9c/interface#");end
end
