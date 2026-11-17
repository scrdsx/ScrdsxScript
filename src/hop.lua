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

-- lowest player count first; keep servers that are not full and have at least MinPlayers; skip ones already tried
local function findServer(bad)
	local best, cursor = {}, nil
	for _ = 1, 6 do
		local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100%s"):format(game.PlaceId, cursor and ("&cursor=" .. cursor) or "")
		local ok, body = pcall(function() return game:HttpGet(url) end)
		if not ok then return nil, "server list request failed (rate limit? wait a few seconds)" end
		local okj, data = pcall(function() return HttpService:JSONDecode(body) end)
		if not okj or type(data) ~= "table" or type(data.data) ~= "table" then return nil, "server list unreadable" end
		for _, s in ipairs(data.data) do
			local playing, max = tonumber(s.playing) or 0, tonumber(s.maxPlayers) or 0
			if s.id ~= game.JobId and not bad[s.id] and playing >= Hop.MinPlayers and playing < max - 1 then
				best[#best + 1] = { id = s.id, playing = playing, max = max }
			end
		end
		-- ascending order: once we have candidates at the lowest qualifying count there is no reason to read on
		if #best >= 3 then break end
		cursor = data.nextPageCursor
		if not cursor then break end
		task.wait(0.4)
	end
	if #best == 0 then return nil, "no server with " .. Hop.MinPlayers .. "+ players found" end
	table.sort(best, function(a, b) return a.playing < b.playing end)
	local low = best[1].playing
	local pool = {}
	for _, s in ipairs(best) do if s.playing == low then pool[#pool + 1] = s end end
	return pool[math.random(#pool)]
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
