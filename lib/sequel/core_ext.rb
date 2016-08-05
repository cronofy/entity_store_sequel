module Sequel
  def self.parse_json(json)
    PigeonHole.parse(json)
  end
end
