-- Quick repair: fires the same server call the tuning garage's "Repair Vehicle" button fires (found in the game's own code, 2026-11-17).
-- The server decides whether it accepts it (it may require the garage menu to be open, and the garage price is charged like normal), so after every
-- press the car's health is checked and the result is reported honestly: repaired / nothing changed.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

local REMOTE = "448bc181-c574-4f60-97d6-94cdf01b13eb"
local Repair = { Auto = false, Threshold = 40, Notify = nil, Info = "ready", Count = 0, Tried = 0, Worked = 0 }

local cache
local function remote()
	if cache and cache.Parent then return cache end
	cache = nil
	for _, d in ipairs(RS:GetDescendants()) do
		if d.Name == REMOTE and d:IsA("RemoteEvent") then cache = d; break end
	end
	return cache
end

local function car()
	local vf = workspace:FindFirstChild("Vehicles")
	return vf and vf:FindFirstChild(lp.Name)
end

local peak, peakCar = 0, nil
local function health(c)
	local h = c and tonumber(c:GetAttribute("currentHealth"))
	if h then
		if peakCar ~= c then peakCar, peak = c, h end
		if h > peak then peak = h end
	end
	return h
end
function Repair.Percent()
	local c = car()
	local h = health(c)
	if not h or peak <= 0 then return nil end
	return math.clamp(h / peak * 100, 0, 100)
end

local busy = false
function Repair.Run(quiet)
	if busy then return end
	local c = car()
	if not c then if not quiet and Repair.Notify then Repair.Notify("Quick repair: you have no vehicle out") end return end
	local r = remote()
	if not r then if not quiet and Repair.Notify then Repair.Notify("Quick repair: the repair remote was not found (the game was updated?)") end return end
	local before = health(c)
	local flatBefore = tostring(c:GetAttribute("flatTires") or "")
	busy = true
	Repair.Tried = Repair.Tried + 1
	pcall(function() r:FireServer() end)
	task.spawn(function()
		local t0 = os.clock()
		local changed = false
		while os.clock() - t0 < 2 do
			task.wait(0.15)
			local h = health(c)
			if (h and before and h > before + 0.5) or tostring(c:GetAttribute("flatTires") or "") ~= flatBefore then changed = true; break end
		end
		busy = false
		if changed then
			Repair.Worked = Repair.Worked + 1
			Repair.Info = "repaired"
			if Repair.Notify then Repair.Notify("Vehicle repaired", 2.5, "success") end
		else
			Repair.Info = "no change"
			if not quiet and Repair.Notify then
				Repair.Notify((before and peak > 0 and before >= peak - 0.5) and "Quick repair: the vehicle is not damaged"
					or "Quick repair: the server did not repair it (it probably needs the tuning garage open, or you cannot afford it)", 3.5, "warn")
			end
		end
	end)
end

local running
function Repair.Start()
	if running then return end
	running = true
	task.spawn(function()
		local last = 0
		while running do
			task.wait(0.5)
			if Repair.Auto and not busy and os.clock() - last > 4 then
				local p = Repair.Percent()
				if p and p <= Repair.Threshold then last = os.clock(); pcall(Repair.Run, true) end
			end
		end
	end)
end

function Repair.Destroy() running = false; Repair.Auto = false; Repair.Notify = nil end

return Repair
