-- Server hop: joins the emptiest public server that still has enough players to have police, then checks the police count
-- after joining and (optionally) hops again until a server really has some. The list comes from Roblox's public servers API.
-- Police per server cannot be read from outside, so "enough players" is the guess and the check after joining is the proof.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local lp = Players.LocalPlayer
local env = getgenv and getgenv() or _G

local FILE = "scrdsx_hop.json"
local Hop = { MinPlayers = 8, MinPolice = 2, Auto = true, Notify = nil, Busy = false, Info = "ready" }
local alive = true

local function note(msg, secs, kind) if Hop.Notify then Hop.Notify(msg, secs or 3, kind) end end

local function loadState()
	if type(readfile) ~= "function" then return {} end
	local ok, d = pcall(function() return HttpService:JSONDecode(readfile(FILE)) end)
	return (ok and type(d) == "table") and d or {}
end
local function saveState(s)
	if type(writefile) == "function" then pcall(function() writefile(FILE, HttpService:JSONEncode(s)) end) end
end

local function policeCount()
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= lp and p.Team and p.Team.Name == "Police" then n = n + 1 end
	end
	return n
end

local CACHE = "scrdsx_hop_cache.json"

-- one page of the server list; Roblox answers 429 when asked too often, so wait and retry instead of giving up
local function fetchPage(cursor)
	local errs = {}
	for attempt = 1, 5 do
		local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100%s"):format(game.PlaceId, cursor and ("&cursor=" .. cursor) or "")
		local body, status
		if type(request) == "function" then
			local okr, res = pcall(request, { Url = url, Method = "GET" })
			if okr and type(res) == "table" then body, status = res.Body, res.StatusCode end
		end
		if not body then
			local ok, b = pcall(function() return game:HttpGet(url) end)
			if ok then body, status = b, 200 else status = tostring(b):find("429", 1, true) and 429 or 0 end
		end
		if status == 429 then
			local wait = 4 + attempt * 4
			note(("Roblox is rate limiting the list, retrying in %ds (%d/5)"):format(wait, attempt), wait, "warn")
			task.wait(wait)
		elseif type(body) == "string" then
			local okj, d = pcall(function() return HttpService:JSONDecode(body) end)
			if okj and type(d) == "table" and type(d.data) == "table" then return d end
			errs[#errs + 1] = "status " .. tostring(status) .. ": " .. body:sub(1, 50):gsub("%s+", " ")
			break
		else
			errs[#errs + 1] = "no answer"
			break
		end
	end
	return nil, table.concat(errs, " | ")
end

-- lowest player count first; keep servers that are not full and have at least MinPlayers; skip ones already tried.
-- The list is cached for a few minutes so hopping again (and auto-hop) does not ask Roblox again and get rate limited.
local function pick(list, bad)
	local ok = {}
	for _, s in ipairs(list) do
		if s.id ~= game.JobId and not bad[s.id] and s.playing >= Hop.MinPlayers and s.playing < s.max - 1 then ok[#ok + 1] = s end
	end
	if #ok == 0 then return nil end
	table.sort(ok, function(a, b) return a.playing < b.playing end)
	local pool = {}
	for _, s in ipairs(ok) do if s.playing == ok[1].playing then pool[#pool + 1] = s end end
	return pool[math.random(#pool)]
end

local function findServer(bad)
	if type(readfile) == "function" then
		local okc, c = pcall(function() return HttpService:JSONDecode(readfile(CACHE)) end)
		if okc and type(c) == "table" and c.place == game.PlaceId and os.time() - (tonumber(c.t) or 0) < 240 and type(c.list) == "table" then
			local s = pick(c.list, bad)
			if s then return s end
		end
	end
	local all, cursor = {}, nil
	for _ = 1, 3 do
		local data, err = fetchPage(cursor)
		if not data then
			if #all == 0 then return nil, "server list failed: " .. tostring(err) end
			break
		end
		for _, s in ipairs(data.data) do
			local playing, max = tonumber(s.playing) or 0, tonumber(s.maxPlayers) or 0
			if playing >= 3 then all[#all + 1] = { id = s.id, playing = playing, max = max } end
		end
		cursor = data.nextPageCursor
		if not cursor or #all >= 40 then break end
		task.wait(1)
	end
	if type(writefile) == "function" then pcall(function() writefile(CACHE, HttpService:JSONEncode({ place = game.PlaceId, t = os.time(), list = all })) end) end
	local s = pick(all, bad)
	if not s then return nil, "no server with " .. Hop.MinPlayers .. "+ players found" end
	return s
end

local function queueReload()
	if type(queue_on_teleport) ~= "function" then return false end
	local src = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/scrdsx/ScrdsxScript/main/loader.lua?t=" .. os.time()))()'
	pcall(queue_on_teleport, src)
	return true
end

-- hop = find a server and teleport. state carries the tried servers and the try count across teleports
function Hop.Go(fromAuto)
	if Hop.Busy then return end
	Hop.Busy = true
	task.spawn(function()
		local st = loadState()
		local bad = {}
		if fromAuto and type(st.bad) == "table" then for _, id in ipairs(st.bad) do bad[id] = true end end
		local tries = fromAuto and (tonumber(st.tries) or 0) or 0
		note("Looking for a server...", 2)
		local s, why = findServer(bad)
		if not s then Hop.Busy = false; Hop.Info = why; note(why, 4, "warn"); return end
		local list = {}
		for id in pairs(bad) do list[#list + 1] = id end
		list[#list + 1] = game.JobId
		saveState({ pending = true, auto = Hop.Auto, from = game.JobId, t = os.time(), tries = tries + 1, bad = list, minPolice = (fromAuto and tonumber(st.minPolice)) or Hop.MinPolice })
		queueReload()
		note(("Joining a server with %d/%d players"):format(s.playing, s.max), 4, "success")
		local ok, err = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, lp) end)
		if not ok then Hop.Busy = false; note("Teleport failed: " .. tostring(err), 4, "warn") end
		-- if the teleport fails (full / gone) the game stays loaded: let the player press again
		task.delay(25, function() Hop.Busy = false end)
	end)
end

-- after arriving: wait for the player list to fill, count police, stop or hop on
function Hop.Start()
	local st = loadState()
	if not (st.pending and os.time() - (tonumber(st.t) or 0) < 180 and st.from ~= game.JobId) then return end
	task.spawn(function()
		task.wait(9) -- teams and players take a moment to arrive
		if not alive then return end
		local need = tonumber(st.minPolice) or Hop.MinPolice
		local n = policeCount()
		if n >= need then
			saveState({})
			note(("Server has %d police and %d players, good to rob"):format(n, #Players:GetPlayers()), 6, "success")
			return
		end
		local tries = tonumber(st.tries) or 1
		if st.auto and tries < 8 then
			note(("Only %d police here, hopping again (%d/8)"):format(n, tries), 3, "warn")
			Hop.Auto = true
			Hop.Go(true)
		else
			saveState({})
			note(("Only %d police in this server"):format(n), 5, "warn")
		end
	end)
end

function Hop.Destroy() alive = false end

return Hop
