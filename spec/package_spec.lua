-- Prueba tools/package.sh, el script que genera el zip de las releases.
-- Necesita sh, zip y unzip (los trae la imagen de tools/Dockerfile).

local function shellQuote(text)
  return "'" .. string.gsub(text, "'", "'\\''") .. "'"
end

-- Ejecuta un comando y devuelve si terminó bien y su salida (estándar y de error juntas).
local function run(command)
  local outputFile = os.tmpname()
  local status = os.execute(command .. " > " .. shellQuote(outputFile) .. " 2>&1")
  local handle = assert(io.open(outputFile, "r"))
  local output = handle:read("*a")
  handle:close()
  os.remove(outputFile)
  return status == 0 or status == true, output
end

local function makeTemporaryDirectory()
  local path = os.tmpname()
  os.remove(path)
  local succeeded, output = run("mkdir -p " .. shellQuote(path))
  assert(succeeded, output)
  return path
end

local function tocVersion()
  for line in io.lines("Richarsilus/Richarsilus.toc") do
    local version = string.match(line, "^## Version:%s*(%S+)")
    if version then
      return version
    end
  end
  error("the TOC has no version")
end

local function package(environment, argument)
  local command = environment .. " sh tools/package.sh"
  if argument then
    command = command .. " " .. shellQuote(argument)
  end
  return run(command)
end

local function zipEntries(archive)
  local succeeded, output = run("unzip -Z1 " .. shellQuote(archive))
  assert(succeeded, output)
  local entries = {}
  for entry in string.gmatch(output, "[^\n]+") do
    entries[entry] = true
  end
  return entries
end

local function fileExists(path)
  local handle = io.open(path, "r")
  if handle then
    handle:close()
    return true
  end
  return false
end

describe("tools/package.sh", function()
  local distDirectory
  local version

  before_each(function()
    distDirectory = makeTemporaryDirectory()
    version = tocVersion()
  end)

  after_each(function()
    run("rm -rf " .. shellQuote(distDirectory))
  end)

  local function distEnvironment()
    return "DIST_DIRECTORY=" .. shellQuote(distDirectory)
  end

  it("packages the addon folder under Richarsilus/ named after the TOC version", function()
    local succeeded, output = package(distEnvironment())
    assert.is_true(succeeded, output)
    local archive = distDirectory .. "/Richarsilus-" .. version .. ".zip"
    assert.are.equal(archive, (string.gsub(output, "%s+$", "")))

    local entries = zipEntries(archive)
    assert.is_true(entries["Richarsilus/Richarsilus.toc"])
    for line in io.lines("Richarsilus/Richarsilus.toc") do
      local file = string.match(line, "^%s*([^#%s].-)%s*$")
      if file then
        local entry = "Richarsilus/" .. string.gsub(file, "\\", "/")
        assert.is_true(entries[entry], "missing from the zip: " .. entry)
      end
    end
    for entry in pairs(entries) do
      assert.is_truthy(string.find(entry, "^Richarsilus/"), "unexpected entry: " .. entry)
    end
  end)

  it("accepts a release tag that matches the TOC version", function()
    local succeeded, output = package(distEnvironment(), "v" .. version)
    assert.is_true(succeeded, output)
    assert.is_true(fileExists(distDirectory .. "/Richarsilus-" .. version .. ".zip"))
  end)

  it("refuses a release tag that does not match the TOC version", function()
    local succeeded, output = package(distEnvironment(), "v999.0.0")
    assert.is_false(succeeded)
    assert.is_truthy(string.find(output, "does not match the TOC version", 1, true))
    assert.is_false(fileExists(distDirectory .. "/Richarsilus-" .. version .. ".zip"))
  end)

  describe("with a copy of the addon", function()
    local addonDirectory

    before_each(function()
      addonDirectory = makeTemporaryDirectory() .. "/Addon"
      local succeeded, output = run("cp -R Richarsilus " .. shellQuote(addonDirectory))
      assert.is_true(succeeded, output)
    end)

    after_each(function()
      run("rm -rf " .. shellQuote(string.match(addonDirectory, "^(.*)/Addon$")))
    end)

    local function environment()
      return distEnvironment() .. " ADDON_DIRECTORY=" .. shellQuote(addonDirectory)
    end

    it("names the folder inside the zip Richarsilus whatever the source folder is called", function()
      local succeeded, output = package(environment())
      assert.is_true(succeeded, output)
      local entries = zipEntries(distDirectory .. "/Richarsilus-" .. version .. ".zip")
      assert.is_true(entries["Richarsilus/Core/Events.lua"])
    end)

    it("fails when a file listed in the TOC is missing", function()
      os.remove(addonDirectory .. "/Core/Money.lua")
      local succeeded, output = package(environment())
      assert.is_false(succeeded)
      assert.is_truthy(string.find(output, "listed in the TOC but missing: Core/Money.lua", 1, true))
    end)

    it("fails when a Lua file is not listed in the TOC", function()
      local handle = assert(io.open(addonDirectory .. "/Core/Forgotten.lua", "w"))
      handle:write("local _ = ...\n")
      handle:close()
      local succeeded, output = package(environment())
      assert.is_false(succeeded)
      assert.is_truthy(string.find(output, "not listed in the TOC (the game would never load it): Core/Forgotten.lua", 1, true))
    end)

    it("fails when the TOC has no version", function()
      local lines = {}
      for line in io.lines(addonDirectory .. "/Richarsilus.toc") do
        if not string.find(line, "^## Version:") then
          lines[#lines + 1] = line
        end
      end
      local handle = assert(io.open(addonDirectory .. "/Richarsilus.toc", "w"))
      handle:write(table.concat(lines, "\n"), "\n")
      handle:close()
      local succeeded, output = package(environment())
      assert.is_false(succeeded)
      assert.is_truthy(string.find(output, "no '## Version:' line", 1, true))
    end)
  end)
end)
