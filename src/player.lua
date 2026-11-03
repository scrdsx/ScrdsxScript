-- Player mods. Inf Stamina: the game keeps stamina in a plain table { hasStaminaBoost = bool, stamina = 0..1 }
-- (found with tools/stamina_inspect.lua). We locate that table on the heap and hold stamina at 1.
-- UNTESTED beyond the dump: if the server also tracks stamina, it can still refuse sprints.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Player = { InfStamina = false, Info = "off" }
local lp = Players.LocalPlayer
local state, scanning, lastScan = nil, false, 0
local conn, charConn

local function valid(t)
	return type(t) == "table" and type(rawget(t, "stamina")) == "number" and rawget(t, "hasStaminaBoost") ~= nil
end

local function small(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
		if n > 6 then return false end
	end
	return true
end

local function say(s)
	if Player.Info ~= s then Player.Info = s; if Player.Changed then Player.Changed() end end
end

-- heap scan in chunks so it never freezes the game
local function scan()
	if scanning then return end
	if not getgc then say("needs getgc (executor)"); return end
	scanning, lastScan = true, os.clock()
	task.spawn(function()
		local ok, heap = pcall(getgc, true)
		if ok then
			for i, t in ipairs(heap) do
				if i % 3000 == 0 then task.wait() end
				if valid(t) and small(t) then state = t break end
			end
		end
		scanning = false
		say(state and "stamina state found" or "stamina state not found (retrying)")
	end)
end

function Player.SetInfStamina(v)
	Player.InfStamina = v
	if v then
		state = nil
		scan()
	else
		say("off")
	end
end

function Player.Start()
	conn = RunService.Heartbeat:Connect(function()
		if not Player.InfStamina then return end
		if state and valid(state) then
			if state.stamina < 1 then state.stamina = 1 end
		elseif os.clock() - lastScan > 3 then
			state = nil
			scan()
		end
	end)
	charConn = lp.CharacterAdded:Connect(function()
		state = nil -- the game may rebuild its stamina state for the new character
		if Player.InfStamina then task.delay(1.5, scan) end
	end)
end

function Player.Destroy()
	Player.InfStamina = false
	if conn then conn:Disconnect(); conn = nil end
	if charConn then charConn:Disconnect(); charConn = nil end
end

return Player
