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

local function changed() if Loot.Changed then task.defer(Loot.Changed) end end
local function say(s) Loot.Info = s; changed() end

local cache
local function interact()
	if cache and cache.Parent then return cache end
	local folder = RS:FindFirstChild("mBd")
	cache = folder and folder:FindFirstChild(INTERACT)
	if not cache then
		for _, d in ipairs(RS:GetDescendants()) do
			if d.Name == INTERACT then cache = d; break end
		end
	end
	return cache
end

local function fire(part, id, mode)
	local r = interact()
	if r then pcall(function() r:FireServer(part, id, mode) end) end
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
	if #list == 0 then
		if not quiet then
			notify(near and ("Quick loot: nothing in reach (nearest pile is %d st away; the game only lets you pick up within 10 st)"):format(near)
				or "Quick loot: nothing collectable is loaded right now")
		end
		return false
	end
	Loot.Busy, Loot.Cancel = true, false
	task.spawn(function()
		local got = 0
		local ok, err = pcall(function()
			for _ = 1, 3 do
				local hh = root()
				if not hh or Loot.Cancel then break end
				local l = candidates(hh)
				if #l == 0 then break end
				say(("picking up %d at once"):format(#l))
				hold(l)
				task.wait(0.25)
				for _, it in ipairs(l) do
					if not it.part.Parent or (it.id ~= ACT.drop and it.part:GetAttribute("Enabled") ~= true) then got = got + 1 end
				end
			end
		end)
		if not ok then warn("[loot] " .. tostring(err)) end
		Loot.Busy, Loot.Cancel = false, false
		Loot.Count = Loot.Count + got
		say(("last: picked up %d"):format(got))
		if got > 0 or not quiet then notify(("Quick loot: picked up %d"):format(got)) end
	end)
	return true
end

function Loot.Stop() Loot.Cancel = true end

-- auto mode: whenever something is in reach, pick it up
local running
function Loot.Start()
	if running then return end
	running = true
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
