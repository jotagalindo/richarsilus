local loader = require("loader")

describe("Money.Format", function()
  local Money

  before_each(function()
    Money = loader.load({ "Core/Init.lua", "Core/Money.lua" }).Money
  end)

  it("formats zero as copper", function()
    assert.are.equal("0c", Money.Format(0))
  end)

  it("formats copper only", function()
    assert.are.equal("5c", Money.Format(5))
  end)

  it("formats gold, silver and copper", function()
    assert.are.equal("1g 2s 3c", Money.Format(10203))
  end)

  it("omits zero parts", function()
    assert.are.equal("1g", Money.Format(10000))
    assert.are.equal("1s 50c", Money.Format(150))
    assert.are.equal("3g 7c", Money.Format(30007))
  end)

  it("formats negative amounts with a minus sign", function()
    assert.are.equal("-2s 50c", Money.Format(-250))
  end)

  it("rounds fractional copper", function()
    assert.are.equal("13c", Money.Format(12.6))
  end)

  it("treats nil as zero", function()
    assert.are.equal("0c", Money.Format(nil))
  end)

  it("colors the coin letters like the game does", function()
    assert.are.equal("1|cffffd100g|r 2|cffc7c7cfs|r 3|cffeda55fc|r", Money.FormatColored(10203))
    assert.are.equal("-50|cffeda55fc|r", Money.FormatColored(-50))
  end)
end)
