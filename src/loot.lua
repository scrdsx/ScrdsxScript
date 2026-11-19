-- Quick loot: picks up EVERYTHING within reach of where you stand, all at the same moment (money piles, gold, items, money on the floor).
-- The server only accepts a pickup when you are within 10 studs of it, so this does not walk: stand in the middle of the loot and press the key.
-- All pickups are held together (they take ~2.5 s each, in parallel), then a second and third round collect whatever the first one missed.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local lp = Players.LocalPlayer

local INTERACT = "b086536b-ee12-4a6c-94c2-0e8040e360ff" -- (target, actionId, "start" | "stop" | "cancel"); read from the game code 2026-11-18 (auto-discovery finds it again after the next rename)
local ACT = { money = "mbm", item = "zl4", drop = "xY3", itemdrop = "Azn" } -- drop ids read 2026-11-18; money / item still the old ones until learned
local REACH = 9.5

local Loot = { Auto = false, Busy = false, Cancel = false, Info = "ready", Count = 0, Notify = nil, Changed = nil }

local lines = {}
local function log(m)
	lines[#lines + 1] = os.date("%H:%M:%S") .. "  " .. m
	if #lines > 200 then table.remove(lines, 1) end
	pcall(function() if writefile then writefile("scrdsx_loot_log.txt", table.concat(lines, "\n")) end end)
end
local function changed() if Loot.Changed then task.defer(Loot.Changed) end end
local function say(s) Loot.Info = s; changed() end

local cache
local function interact()
	if cache and cache.Parent then return cache end
	cache = nil
	for _, d in ipairs(RS:GetDescendants()) do
		if d.Name == INTERACT and d:IsA("RemoteEvent") then cache = d; break end
	end
	return cache
end

-- SELF-LEARNING: the game renames its remotes and action ids when it updates, so the old fixed ones stopped working. A passive hook watches every
-- FireServer; the first time you pick something up by hand (hold E on money / an item), the real remote and action ids are learned from that call.
local hooked
local seenSig = {}
local renamed = false     -- the hard-coded remote did not exist: the game changed it, so the ids may have changed too

-- AUTO-DISCOVERY: the game's own pickup code calls ClientEvents["<guid>"](instance, id, "start" / "stop" / "cancel"). Scan the running Lua functions for the
-- guid that sits together with those three words; that is the pickup remote, whatever the game renamed it to.
local lastDiscover = -99
local function discover()
	if os.clock() - lastDiscover < 20 then return false end
	lastDiscover = os.clock()
	if type(getgc) ~= "function" or not (debug and type(debug.getconstants) == "function") then log("auto-discovery unavailable (needs getgc + debug.getconstants)"); return false end
	local ok, res = pcall(function()
		local seen = {}
		local gc = getgc(false)
		for i = 1, #gc do
			local f = gc[i]
			if type(f) == "function" then
				local okc, cs = pcall(debug.getconstants, f)
				if okc and type(cs) == "table" then
					local guids, w = {}, {}
					for _, c in pairs(cs) do
						if type(c) == "string" then
							if #c == 36 and c:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then guids[#guids + 1] = c
							elseif c == "start" or c == "stop" or c == "cancel" then w[c] = true end
						end
					end
					for _, g in ipairs(guids) do
						local t = seen[g]; if not t then t = {}; seen[g] = t end
						for k in pairs(w) do t[k] = true end
					end
				end
			end
			if i % 4000 == 0 then task.wait() end
		end
		for g, t in pairs(seen) do
			if t.start and t.stop and t.cancel then
				for _, d in ipairs(RS:GetDescendants()) do
					if d.Name == g and d:IsA("RemoteEvent") then return g end
				end
			end
		end
	end)
	if ok and res then
		if res ~= INTERACT then log("DISCOVERED the pickup remote: " .. res); INTERACT = res; cache = nil end
		return true
	end
	log("auto-discovery found nothing" .. (ok and "" or (": " .. tostring(res))))
	return false
end

-- AUTO-DISCOVERY OF THE ACTION IDS: the game builds one component object per pickup part, and each answers :getIdentifier() with the id it sends to the server.
-- Find those objects in memory (a table with .instance = the tagged part) and ask them, so no manual pickup is needed.
local ID_TAGS = {
	{ "Money Collect Interactable", "money" }, { "Item Collect Interactable", "item" },
	{ "Money Drop Interactable", "drop" }, { "Item Drop Interactable", "itemdrop" },
}
local lastIds = -99
local function discoverIds()
	if os.clock() - lastIds < 15 then return false end
	lastIds = os.clock()
	if type(getgc) ~= "function" then return false end
	local found = {}
	local ok, err = pcall(function()
		local gc = getgc(true)
		for i = 1, #gc do
			local t = gc[i]
			if type(t) == "table" then
				local okI, inst = pcall(rawget, t, "instance")
				if okI and typeof(inst) == "Instance" then
					for _, tg in ipairs(ID_TAGS) do
						if not found[tg[2]] and CS:HasTag(inst, tg[1]) then
							local okId, id = pcall(function() return t:getIdentifier() end)
							if okId and type(id) == "string" and #id > 0 and #id <= 8 then found[tg[2]] = id end
						end
					end
				end
			end
			if i % 5000 == 0 then task.wait() end
		end
	end)
	if not ok then log("id discovery error: " .. tostring(err)); return false end
	local n = 0
	for k, id in pairs(found) do
		n = n + 1
		if ACT[k] ~= id then log(("DISCOVERED action id for %s: %s (was %s)"):format(k, id, tostring(ACT[k]))); ACT[k] = id end
	end
	if n > 0 then Loot.Learned = true; changed() else log("id discovery found no pickup objects (are you near a loaded pile?)") end
	return n > 0
end

-- hold E for a few seconds so the game's own pickup fires once; the learner below reads the remote + action id from that call
local function assistHold()
	local ok = pcall(function()
		local vim = game:GetService("VirtualInputManager")
		vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
		task.wait(3)
		vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
	end)
	return ok
end
local function describe(v)
	if typeof(v) == "Instance" then
		local tags = {}
		pcall(function() for _, t in ipairs(CS:GetTags(v)) do tags[#tags + 1] = t end end)
		return v:GetFullName() .. (#tags > 0 and (" {" .. table.concat(tags, "|") .. "}") or "")
	end
	return typeof(v) .. ":" .. tostring(v)
end
local function onFire(remote, ...)
	local a = { ... }
	local p, id, mode = a[1], a[2], a[3]
	if typeof(p) == "Instance" and type(id) == "string" and mode == "start" then
		local money = CS:HasTag(p, "Money Collect Interactable")
		local item = CS:HasTag(p, "Item Collect Interactable")
		local drop = p.Parent == workspace:FindFirstChild("Drops")
		if money or item or drop then
			if cache ~= remote then
				cache = remote
				INTERACT = remote.Name
				log("LEARNED the pickup remote: " .. remote:GetFullName())
				if Loot.Notify then Loot.Notify("Quick loot learned the new pickup remote") end
			end
			local key = money and "money" or (item and "item" or "drop")
			if ACT[key] ~= id then ACT[key] = id; log(("LEARNED action id for %s: %s"):format(key, id)) end
			Loot.Learned = true
			changed()
		end
	end
	-- record each distinct kind of call once (name + argument types) so unknown actions (bombs, throwing...) can be read from the log
	local parts = {}
	for i = 1, math.min(#a, 5) do parts[#parts + 1] = typeof(a[i]) == "Instance" and "Instance" or (type(a[i]) == "string" and a[i] or typeof(a[i])) end
	local sig = remote.Name .. "|" .. table.concat(parts, ",")
	if not seenSig[sig] and #lines < 150 then
		seenSig[sig] = true
		local d = {}
		for i = 1, math.min(#a, 5) do d[#d + 1] = describe(a[i]) end
		log(("FireServer %s (%s) args: %s"):format(remote.ClassName, remote:GetFullName(), table.concat(d, "  ,  ")))
	end
end
local function installHook()
	if hooked then return end
	if type(hookfunction) ~= "function" then log("hookfunction is missing: the pickup remote cannot be learned automatically"); return end
	local ok, err = pcall(function()
		local old
		old = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
			if typeof(self) == "Instance" and self.ClassName == "RemoteEvent" then pcall(onFire, self, ...) end
			return old(self, ...)
		end)
	end)
	hooked = ok
	log(ok and "pickup learner installed (pick something up by hand once)" or ("learner failed: " .. tostring(err)))
end

local function fire(part, id, mode)
	local r = interact()
	if not r then return false end
	local ok, err = pcall(function() r:FireServer(part, id, mode) end)
	if not ok then log("FireServer failed: " .. tostring(err)) end
	return ok
end

local function root()
	local c = lp.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function candidates(h)
	local list, near = {}, nil
	local function add(d, id)
		if d:IsA("BasePart") then
			local dd = (d.Position - h.Position).Magnitude
			if not near or dd < near then near = dd end
			if dd <= REACH then list[#list + 1] = { part = d, id = id } end
		end
	end
	for _, d in ipairs(CS:GetTagged("Money Collect Interactable")) do
		if d:GetAttribute("Enabled") == true then add(d, ACT.money) end
	end
	for _, d in ipairs(CS:GetTagged("Item Collect Interactable")) do
		if d:GetAttribute("Enabled") == true and d:GetAttribute("Collectable") ~= false then add(d, ACT.item) end
	end
	-- dropped money / items: citizens can only take their own (the part is named after the player), police can confiscate any
	local police = lp.Team and lp.Team.Name == "Police"
	for _, d in ipairs(CS:GetTagged("Money Drop Interactable")) do
		if police or d.Name == lp.Name then add(d, ACT.drop) end
	end
	for _, d in ipairs(CS:GetTagged("Item Drop Interactable")) do
		if police or d.Name == lp.Name then add(d, ACT.itemdrop) end
	end
	return list, near
end

local function hold(items)
	for _, it in ipairs(items) do fire(it.part, it.id, "start") end
	local t = os.clock()
	while os.clock() - t < 2.52 do
		if Loot.Cancel then
			for _, it in ipairs(items) do fire(it.part, it.id, "cancel") end
			return false
		end
		task.wait(0.1)
	end
	for _, it in ipairs(items) do fire(it.part, it.id, "stop") end
	return true
end

local function notify(msg) if Loot.Notify then Loot.Notify(msg) end end

-- one quick loot; quiet = no "nothing here" message (used by the auto mode)
function Loot.Run(quiet)
	if Loot.Busy then return false end
	local h = root()
	if not h then return false end
	if not Loot.Learned then pcall(discoverIds) end
	local list, near = candidates(h)
	if not interact() then
		renamed = true
		if discover() and interact() then
			log("continuing with the discovered remote")
		end
	end
	if renamed and not Loot.Learned and #list > 0 and hooked and not Loot.Assisting then
		-- the ids may be stale after a game update: let the game fire one real pickup so they are learned
		Loot.Assisting = true
		notify("Quick loot: learning the game's new pickup ids (holding E for 3 s, stay next to the loot)")
		assistHold()
		Loot.Assisting = false
		list, near = candidates(h)
		log(Loot.Learned and "ids learned from the assisted pickup" or "assist did not produce a pickup call")
	end
	if not interact() then
		if not quiet then
			log("pickup remote unknown: waiting for a manual pickup to learn it")
			notify(hooked and "Quick loot: the game changed its pickup remote. Pick up ONE item by hand (hold E) and I learn the new one automatically."
				or "Quick loot: the game changed its pickup remote and your executor has no hookfunction to learn the new one")
		end
		return false
	end
	if #list == 0 then
		local tagged, enabled = 0, 0
		for _, tg in ipairs({ "Money Collect Interactable", "Item Collect Interactable", "Money Drop Interactable", "Item Drop Interactable" }) do
			for _, d in ipairs(CS:GetTagged(tg)) do
				tagged = tagged + 1
				if d:GetAttribute("Enabled") == true then enabled = enabled + 1 end
			end
		end
		log(("nothing in reach: tagged piles loaded=%d, enabled=%d, nearest=%s"):format(tagged, enabled, near and (math.floor(near) .. " st") or "none"))
		if not quiet then
			notify(near and ("Quick loot: nothing in reach (nearest pile is %d st away; the game only lets you pick up within 10 st)"):format(near)
				or "Quick loot: nothing collectable is loaded right now")
		end
		return false
	end
	Loot.Busy, Loot.Cancel = true, false
	log(("starting: %d pile(s) in reach, in a car: %s"):format(#list, tostring(lp.Character and lp.Character:FindFirstChildOfClass("Humanoid") and lp.Character:FindFirstChildOfClass("Humanoid").SeatPart ~= nil)))
	task.spawn(function()
		local got = 0
		local ok, err = pcall(function()
			for _ = 1, 3 do
				local hh = root()
				if not hh or Loot.Cancel then break end
				local l = candidates(hh)
				if #l == 0 then break end
				say(("picking up %d at once"):format(#l))
				log(("round: holding %d pickups"):format(#l))
				hold(l)
				task.wait(0.25)
				for _, it in ipairs(l) do
					if not it.part.Parent or ((it.id == ACT.money or it.id == ACT.item) and it.part:GetAttribute("Enabled") ~= true) then got = got + 1 end
				end
			end
		end)
		if not ok then warn("[loot] " .. tostring(err)) end
		Loot.Busy, Loot.Cancel = false, false
		log(("done: %d picked up"):format(got))
		Loot.Count = Loot.Count + got
		say(("last: picked up %d"):format(got))
		if got > 0 or not quiet then notify(("Quick loot: picked up %d"):format(got)) end
		if got == 0 and not quiet then
			-- nothing accepted: re-read the ids from the game's own objects (works without picking anything up by hand)
			lastIds = -99
			task.spawn(function()
				if discoverIds() then notify("Quick loot: refreshed the pickup ids from the game, press the key again") end
			end)
		end
		if got == 0 and not Loot.Learned and hooked and not quiet then
			-- the server ignored the call: the pickup ids are probably stale. One real pickup by hand lets the learner read the right ones.
			notify("Quick loot: the game did not accept the pickup. Hold E on ONE pile by hand and I learn the new ids automatically.")
			log("0 picked up and nothing learned yet: waiting for one manual pickup")
		end
	end)
	return true
end

function Loot.Stop() Loot.Cancel = true end

-- USE ALL: equips and uses every tool whose name contains `pat` (e.g. "bomb") one after another, as fast as the game allows.
-- A single tool that is a stack (it has an Amount / Quantity / Count attribute) is used that many times.
function Loot.UseAll(pat)
	pat = (pat or ""):lower()
	if pat == "" then notify("Use all: type an item name first (for example bomb)"); return 0 end
	local ch = lp.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return 0 end
	local tools = {}
	for _, holder in ipairs({ lp.Backpack, ch }) do
		for _, t in ipairs(holder:GetChildren()) do
			if t:IsA("Tool") and t.Name:lower():find(pat, 1, true) then tools[#tools + 1] = t end
		end
	end
	if #tools == 0 then notify("Use all: no item with \"" .. pat .. "\" in your inventory"); return 0 end
	task.spawn(function()
		local used = 0
		for _, t in ipairs(tools) do
			if t.Parent then
				local n = t:GetAttribute("Amount") or t:GetAttribute("Quantity") or t:GetAttribute("Count") or 1
				if type(n) ~= "number" or n < 1 then n = 1 end
				log(("use all: %s x%d (class %s, attrs: %s)"):format(t.Name, n, t.ClassName, (function()
					local p = {}
					for k, v in pairs(t:GetAttributes()) do p[#p + 1] = k .. "=" .. tostring(v) end
					return table.concat(p, ", ")
				end)()))
				pcall(function() hum:EquipTool(t) end)
				task.wait(0.08)
				for _ = 1, math.min(n, 25) do
					pcall(function() t:Activate() end)
					used = used + 1
					task.wait(0.1)
				end
			end
		end
		notify(("Use all: used %d"):format(used))
	end)
	return #tools
end

-- auto mode: whenever something is in reach, pick it up
local running
function Loot.Start()
	if running then return end
	running = true
	installHook()
	if not interact() then
		renamed = true
		log("no remote named " .. INTERACT .. " exists any more; trying auto-discovery")
		task.spawn(function() if discover() then interact() end end)
	end
	task.spawn(function() task.wait(2); pcall(discoverIds) end)
	task.spawn(function()
		while running do
			task.wait(0.6)
			if Loot.Auto and not Loot.Busy then pcall(Loot.Run, true) end
		end
	end)
end

function Loot.Destroy()
	running = false
	Loot.Cancel = true
	Loot.Auto = false
	Loot.Notify, Loot.Changed = nil, nil
end

return Loot
