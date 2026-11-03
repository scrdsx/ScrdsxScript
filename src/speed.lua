-- Speed module: the garage tuning (Engine / Brakes / Armor levels) for free, plus acceleration + top speed multipliers.
-- From tools/tuning_probe.lua: the client reads the car attributes engineLevel / brakesLevel / armorLevel (run B was faster
-- with them set to 5), and its drive code reads acceleration/maxSpeed from ReplicatedStorage.Code.vehicles.configs.
-- Everything here is LOCAL: it never buys anything and everything is restored when you turn the module off.
-- UNTESTED: the multipliers edit the game's shared config table; if the game copies it per car they may not apply (Status says).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Speed = {
	Enabled = false, Engine = 0, Brakes = 0, Armor = 0, AccelMult = 1, TopMult = 1,
	Info = "off",
}
local lp = Players.LocalPlayer
local car, savedAttrs, cfg, savedCfg, applied = nil, nil, nil, nil, {}
local cfgMod, conn, acc = nil, nil, 0
local ATTRS = { engineLevel = "Engine", brakesLevel = "Brakes", armorLevel = "Armor" }

local function currentCar()
	local c = lp.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local s = h and h.SeatPart
	if not s then return nil end
	local m = s:FindFirstAncestorOfClass("Model")
	while m and m.Parent and m.Parent:IsA("Model") do m = m.Parent end
	return m
end

local function loadConfigs()
	if cfgMod ~= nil then return cfgMod end
	cfgMod = false
	local code = RS:FindFirstChild("Code")
	local v = code and code:FindFirstChild("vehicles")
	local inst = v and v:FindFirstChild("configs")
	if inst then
		local ok, m = pcall(require, inst)
		if ok and type(m) == "table" then cfgMod = m end
	end
	return cfgMod
end

local function findConfig(m)
	local mod = loadConfigs()
	if not mod then return nil end
	local t = type(mod.VehicleConfigurations) == "table" and mod.VehicleConfigurations or mod
	local c = t[m:GetAttribute("Config")]
	return type(c) == "table" and c or nil
end

local function writable(t)
	if setreadonly then pcall(setreadonly, t, false) end
end

-- re-run the game's own update code (it listens for the level attributes)
local function retrigger(m)
	local lvl = m:GetAttribute("engineLevel") or 0
	m:SetAttribute("engineLevel", lvl + 0.001)
	m:SetAttribute("engineLevel", lvl)
end

local function restore()
	if car and car.Parent and savedAttrs then
		for a, v in pairs(savedAttrs) do pcall(function() car:SetAttribute(a, v) end) end
	end
	if cfg and savedCfg then
		writable(cfg)
		for k, v in pairs(savedCfg) do pcall(function() cfg[k] = v end) end
	end
	if car and car.Parent and (cfg or savedAttrs) then pcall(retrigger, car) end
	car, savedAttrs, cfg, savedCfg, applied = nil, nil, nil, nil, {}
end

local function apply()
	local m = currentCar()
	if not Speed.Enabled then
		if car then restore() end
		return
	end
	if m ~= car then
		restore()
		car = m
		if m then
			savedAttrs = {}
			for a in pairs(ATTRS) do savedAttrs[a] = m:GetAttribute(a) or 0 end
			cfg = findConfig(m)
			if cfg then
				savedCfg = { maxSpeed = cfg.maxSpeed, maxReverseSpeed = cfg.maxReverseSpeed, acceleration = cfg.acceleration }
			end
		end
	end
	if not car then Speed.Info = "no car (sit in one)"; return end

	local retrig = false
	for a, field in pairs(ATTRS) do
		if car:GetAttribute(a) ~= Speed[field] then car:SetAttribute(a, Speed[field]) end
	end
	if cfg and savedCfg then
		writable(cfg)
		if applied.top ~= Speed.TopMult then
			applied.top = Speed.TopMult
			if type(savedCfg.maxSpeed) == "number" then cfg.maxSpeed = savedCfg.maxSpeed * Speed.TopMult end
			if type(savedCfg.maxReverseSpeed) == "number" then cfg.maxReverseSpeed = savedCfg.maxReverseSpeed * Speed.TopMult end
		end
		if applied.acc ~= Speed.AccelMult then
			applied.acc = Speed.AccelMult
			if type(savedCfg.acceleration) == "number" then cfg.acceleration = savedCfg.acceleration * Speed.AccelMult; retrig = true end
		end
	end
	if applied.lvl ~= Speed.Engine then applied.lvl = Speed.Engine end
	if retrig then pcall(retrigger, car) end
	Speed.Info = ("%s | config %s%s"):format(car.Name, cfg and "ok" or "NOT FOUND (multipliers off)",
		cfg and (" (max %s, accel %s)"):format(tostring(cfg.maxSpeed), tostring(cfg.acceleration)) or "")
end

function Speed.SetEnabled(v)
	Speed.Enabled = v
	acc = 0
	apply()
	if Speed.Changed then Speed.Changed() end
end

function Speed.Start()
	conn = RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < 0.25 then return end
		acc = 0
		local before = Speed.Info
		local ok = pcall(apply)
		if not ok then Speed.Info = "error (see console)" end
		if Speed.Changed and Speed.Info ~= before then Speed.Changed() end
	end)
end

function Speed.Destroy()
	Speed.Enabled = false
	if conn then conn:Disconnect(); conn = nil end
	pcall(restore)
	Speed.Changed = nil
end

return Speed
