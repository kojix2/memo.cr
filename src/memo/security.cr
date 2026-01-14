module Memo
  module Security
    @@token : String = ""

    def self.token : String
      @@token
    end

    def self.token=(value : String)
      @@token = value
    end

    def self.enabled? : Bool
      !@@token.empty?
    end
  end
end
