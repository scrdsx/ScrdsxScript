-- World: lighting (fullbright, no fog, time of day), unlimited camera zoom and movement helpers (infinite jump, noclip, walk speed).
-- Lighting / camera only change what YOUR screen shows. Movement ones are risky: the server may notice them.
-- (Field of view, hold-to-zoom and anti-AFK live in client/utility.lua.)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer

local World = {
	Fullbright = false, NoFog = false, LockTime = false, Time = 14,
	Zoom = false,
	InfJump = false, Noclip = false, SpeedOn = false, Speed = 24,
	Info = "ready",
}

local orig = {}
local function remember()
	if orig.saved then return end
	orig = {
		saved = true, Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
		GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
	}
end
local function restoreLighting()
	if not orig.saved then return end
	pcall(function()
		Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.FogStart = orig.Brightness, orig.ClockTime, orig.FogEnd, orig.FogStart
		Lighting.GlobalShadows, Lighting.Ambient, Lighting.OutdoorAmbient = orig.GlobalShadows, orig.Ambient, orig.OutdoorAmbient
	end)
	orig = {}
end

local conns = {}
local noclipParts = {}
local ncChar, ncT, ncList = nil, 0, {}
local lastLight = 0
local origZoom, origSpeed

local function char() local c = lp.Character; return c, c and c:FindFirstChildOfClass("Humanoid") end

function World.Start()
	if #conns > 0 then return end
	-- infinite jump
	table.insert(conns, UIS.JumpRequest:Connect(function()
		if not World.InfJump then return end
		local _, h = char()
		if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
	end))
	-- lighting (the game changes the time of day itself, so it is re-applied twice a second)
	table.insert(conns, RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastLight > 0.5 then
			lastLight = now
			local want = World.Fullbright or World.NoFog or World.LockTime
			if want then remember() end
			if World.Fullbright then
				Lighting.Brightness = 2
				Lighting.ClockTime = 14
				Lighting.GlobalShadows = false
				Lighting.Ambient = Color3.fromRGB(170, 170, 170)
				Lighting.OutdoorAmbient = Color3.fromRGB(170, 170, 170)
			end
			if World.NoFog then
				Lighting.FogEnd = 1e6
				Lighting.FogStart = 1e6
				local at = Lighting:FindFirstChildOfClass("Atmosphere")
				if at then at.Density = 0; at.Haze = 0 end
			end
			if World.LockTime and not World.Fullbright then Lighting.ClockTime = World.Time end
		end
		-- unlimited camera zoom
		if World.Zoom then
			if not origZoom then origZoom = lp.CameraMaxZoomDistance end
			if lp.CameraMaxZoomDistance ~= 1000 then lp.CameraMaxZoomDistance = 1000 end
		elseif origZoom then
			lp.CameraMaxZoomDistance = origZoom
			origZoom = nil
		end
		-- walk speed
		if World.SpeedOn then
			local _, h = char()
			if h then
				if not origSpeed then origSpeed = h.WalkSpeed end
				h.WalkSpeed = World.Speed
			end
		elseif origSpeed then
			local _, h = char()
			if h then h.WalkSpeed = origSpeed end
			origSpeed = nil
		end
	end))
	-- noclip
	table.insert(conns, RunService.Stepped:Connect(function()
		if World.Noclip then
			local c = char()
			if c then
				-- the character's parts are listed once per character (and re-listed every 2 s for new accessories), not every physics step
				local now = os.clock()
				if ncChar ~= c or now - ncT > 2 then
					ncChar, ncT = c, now
					ncList = {}
					for _, d in ipairs(c:GetDescendants()) do
						if d:IsA("BasePart") then ncList[#ncList + 1] = d end
					end
				end
				for _, d in ipairs(ncList) do
					if d.CanCollide then noclipParts[d] = true; d.CanCollide = false end
				end
			end
		elseif next(noclipParts) then
			for d in pairs(noclipParts) do pcall(function() d.CanCollide = true end) end
			noclipParts = {}
		end
	end))
end

function World.Refresh()
	if not (World.Fullbright or World.NoFog or World.LockTime) then restoreLighting() end
end

function World.Destroy()
	World.Fullbright, World.NoFog, World.LockTime, World.Zoom = false, false, false, false
	World.InfJump, World.Noclip, World.SpeedOn = false, false, false
	pcall(function()
		restoreLighting()
		if origZoom then lp.CameraMaxZoomDistance = origZoom end
		local _, h = char()
		if h and origSpeed then h.WalkSpeed = origSpeed end
		for d in pairs(noclipParts) do d.CanCollide = true end
	end)
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	conns = {}
end

return World
