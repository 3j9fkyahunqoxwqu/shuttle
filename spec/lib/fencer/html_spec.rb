# Copyright 2014 Square Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

require 'rails_helper'

RSpec.describe Fencer::Html do
  describe ".fence" do
    it "should fence out HTML tags" do
      expect(Fencer::Html.fence('String with <token one="two" three-four=five six>two< /token > tokens.')).
          to eql('<token one="two" three-four=five six>' => [12..48], '< /token >' => [52..61])
    end

    it "should fence self-closing tags" do
      expect(Fencer::Html.fence('Hello <br/> world < br / >.')).
          to eql('<br/>' => [6..10], '< br / >' => [18..25])
    end

    it "should not fence out things that look like HTML character tags" do
      expect(Fencer::Html.fence("Hello&; Hello & world ; also 5 > 3 and 2 < 5.")).
                to eql({})
    end
  end

  describe ".valid?" do
    it "should return true for a string with valid XHTML" do
      expect(Fencer::Html.valid?('Some <b id="bar">valid<br /> XHTML</b>.')).to be_truthy
    end

    it "should return true for a string with valid HTML5" do
      expect(Fencer::Html.valid?("Some <b id=bar>valid<br> HTML</b>.")).to be_truthy
    end

    it "should return false for a string with invalid HTML" do
      expect(Fencer::Html.valid?("An <unknown>tag.")).to be_falsey
      expect(Fencer::Html.valid?("An <b>unclosed tag.")).to be_falsey
      expect(Fencer::Html.valid?("A <b>mismatched tag</i>.")).to be_falsey
      expect(Fencer::Html.valid?("An <b>invalid tag.<b>")).to be_falsey
    end
  end
end
