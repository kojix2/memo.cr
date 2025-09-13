require "./spec_helper"

describe Memo do
  it "has a version number" do
    Memo::VERSION.should be_a(String)
  end
end
