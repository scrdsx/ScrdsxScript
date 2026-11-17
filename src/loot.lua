-- Quick loot: picks up EVERYTHING within reach of where you stand, all at the same moment (money piles, gold, items, money on the floor).
-- The server only accepts a pickup when you are within 10 studs of it, so this does not walk: stand in the middle of the loot and press the key.
-- All pickups are held together (they take ~2.5 s each, in parallel), then a second and third round collect whatever the first one missed.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local lp = Players.LocalPlayer

local INTERACT = "e3256932-2913-480f-93e8-9cda8c896b14" -- (target, actionId, "start" | "stop" | "cancel")
local ACT = { money = "2vd", item = "7Rm", drop = "P11" }
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
	for _, tg in ipairs({ "Money Collect Interactable", "Item Collect Interactable" }) do
		for _, d in ipairs(CS:GetTagged(tg)) do
			if d:IsA("BasePart") and d:GetAttribute("Enabled") == true and d:GetAttribute("Collectable") ~= false then
				local dd = (d.Position - h.Position).Magnitude
				if not near or dd < near then near = dd end
				if dd <= REACH then list[#list + 1] = { part = d, id = CS:HasTag(d, "Money Collect Interactable") and ACT.money or ACT.item } end
			end
		end
	end
	local drops = workspace:FindFirstChild("Drops") -- money on the floor: MeshParts named after me
	for _, d in ipairs(drops and drops:GetChildren() or {}) do
		if d.Name == lp.Name and d:IsA("BasePart") then
			local dd = (d.Position - h.Position).Magnitude
			if not near or dd < near then near = dd end
			if dd <= REACH then list[#list + 1] = { part = d, id = ACT.drop } end
		end
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
	local list, near = candidates(h)
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
		for _, tg in ipairs({ "Money Collect Interactable", "Item Collect Interactable" }) do
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
					if not it.part.Parent or (it.id ~= ACT.drop and it.part:GetAttribute("Enabled") ~= true) then got = got + 1 end
				end
			end
		end)
		if not ok then warn("[loot] " .. tostring(err)) end
		Loot.Busy, Loot.Cancel = false, false
		log(("done: %d picked up"):format(got))
		Loot.Count = Loot.Count + got
		say(("last: picked up %d"):format(got))
		if got > 0 or not quiet then notify(("Quick loot: picked up %d"):format(got)) end
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
	if not interact() then log("no remote named " .. INTERACT .. " exists any more; waiting to learn the new one") end
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
