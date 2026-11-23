-- Config files in the executor workspace:  ScrdsxScript/configs/<name>.json   +   ScrdsxScript/autoload.txt (name of the config to load on start)
local HttpService = game:GetService("HttpService")

local Config = {}
local DIR = "ScrdsxScript"
local CFG = DIR .. "/configs"
local AUTO = DIR .. "/autoload.txt"

Config.Available = (writefile and readfile and isfile) ~= nil

local function ensure()
	pcall(function()
		if not makefolder then return end
		if isfolder then
			if not isfolder(DIR) then makefolder(DIR) end
			if not isfolder(CFG) then makefolder(CFG) end
		else
			makefolder(DIR); makefolder(CFG)
		end
	end)
end

function Config.Clean(name)
	name = tostring(name or ""):gsub("[^%w _%-]", "")
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	return name:sub(1, 32)
end

local function path(name) return CFG .. "/" .. name .. ".json" end

function Config.List()
	local out = {}
	if not listfiles then return out end
	ensure()
	local ok, files = pcall(listfiles, CFG)
	if not ok or type(files) ~= "table" then return out end
	for _, f in ipairs(files) do
		local n = tostring(f):match("([^/\\]+)%.json$")
		if n then out[#out + 1] = n end
	end
	table.sort(out, function(a, b) return a:lower() < b:lower() end)
	return out
end

function Config.Exists(name)
	if not (isfile and name and name ~= "") then return false end
	local ok, r = pcall(isfile, path(name))
	return ok and r == true
end

function Config.Read(name)
	if not Config.Exists(name) then return nil end
	local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path(name))) end)
	if ok and type(data) == "table" then return data end
	return nil
end

function Config.Write(name, tbl)
	if not (Config.Available and name and name ~= "") then return false end
	ensure()
	local ok = pcall(function() writefile(path(name), HttpService:JSONEncode(tbl)) end)
	return ok
end

function Config.Delete(name)
	if not (delfile and Config.Exists(name)) then return false end
	return pcall(delfile, path(name))
end

function Config.GetAutoload()
	if not (isfile and readfile) then return nil end
	local ok, r = pcall(function() if isfile(AUTO) then return readfile(AUTO) end end)
	if ok and type(r) == "string" then
		r = Config.Clean(r)
		if r ~= "" then return r end
	end
	return nil
end

function Config.SetAutoload(name)
	if not Config.Available then return false end
	ensure()
	return pcall(function() writefile(AUTO, name or "") end)
end

return Config
