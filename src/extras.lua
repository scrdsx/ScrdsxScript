-- Extras: small client-side helpers. Lighting / camera ones only change what YOUR screen shows. Movement ones are marked risky: the server
-- may notice a changed walk speed or a character walking through walls.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer

local Extras = {
	AntiAfk = true,
	Fullbright = false, NoFog = false, LockTime = false, Time = 14,
	FovOn = false, Fov = 90, Zoom = false,
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
local lastLight = 0
local origFov, origZoom, origSpeed

local function char() local c = lp.Character; return c, c and c:FindFirstChildOfClass("Humanoid") end

function Extras.Start()
	if #conns > 0 then return end
	-- anti AFK: the game never kicks you for standing still
	table.insert(conns, lp.Idled:Connect(function()
		if not Extras.AntiAfk then return end
		pcall(function()
			local vu = game:GetService("VirtualUser")
			vu:CaptureController()
			vu:ClickButton2(Vector2.new())
		end)
	end))
	-- infinite jump
	table.insert(conns, UIS.JumpRequest:Connect(function()
		if not Extras.InfJump then return end
		local _, h = char()
		if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
	end))
	-- lighting (the game changes the time of day itself, so it is re-applied twice a second)
	table.insert(conns, RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastLight > 0.5 then
			lastLight = now
			local want = Extras.Fullbright or Extras.NoFog or Extras.LockTime
			if want then remember() end
			if Extras.Fullbright then
				Lighting.Brightness = 2
				Lighting.ClockTime = 14
				Lighting.GlobalShadows = false
				Lighting.Ambient = Color3.fromRGB(170, 170, 170)
				Lighting.OutdoorAmbient = Color3.fromRGB(170, 170, 170)
			end
			if Extras.NoFog then
				Lighting.FogEnd = 1e6
				Lighting.FogStart = 1e6
				local at = Lighting:FindFirstChildOfClass("Atmosphere")
				if at then at.Density = 0; at.Haze = 0 end
			end
			if Extras.LockTime and not Extras.Fullbright then Lighting.ClockTime = Extras.Time end
		end
		-- walk speed
		if Extras.SpeedOn then
			local _, h = char()
			if h then
				if not origSpeed then origSpeed = h.WalkSpeed end
				h.WalkSpeed = Extras.Speed
			end
		elseif origSpeed then
			local _, h = char()
			if h then h.WalkSpeed = origSpeed end
			origSpeed = nil
		end
	end))
	-- noclip
	table.insert(conns, RunService.Stepped:Connect(function()
		if Extras.Noclip then
			local c = char()
			if c then
				for _, d in ipairs(c:GetDescendants()) do
					if d:IsA("BasePart") and d.CanCollide then noclipParts[d] = true; d.CanCollide = false end
				end
			end
		elseif next(noclipParts) then
			for d in pairs(noclipParts) do pcall(function() d.CanCollide = true end) end
			noclipParts = {}
		end
	end))
	-- camera: field of view and zoom
	table.insert(conns, RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if cam then
			if Extras.FovOn then
				if not origFov then origFov = cam.FieldOfView end
				cam.FieldOfView = Extras.Fov
			elseif origFov then
				cam.FieldOfView = origFov
				origFov = nil
			end
		end
		if Extras.Zoom then
			if not origZoom then origZoom = lp.CameraMaxZoomDistance end
			lp.CameraMaxZoomDistance = 1000
		elseif origZoom then
			lp.CameraMaxZoomDistance = origZoom
			origZoom = nil
		end
	end))
end

function Extras.Refresh()
	if not (Extras.Fullbright or Extras.NoFog or Extras.LockTime) then restoreLighting() end
end

function Extras.Destroy()
	Extras.Fullbright, Extras.NoFog, Extras.LockTime, Extras.FovOn, Extras.Zoom = false, false, false, false, false
	Extras.InfJump, Extras.Noclip, Extras.SpeedOn = false, false, false
	pcall(function()
		restoreLighting()
		local cam = workspace.CurrentCamera
		if cam and origFov then cam.FieldOfView = origFov end
		if origZoom then lp.CameraMaxZoomDistance = origZoom end
		local _, h = char()
		if h and origSpeed then h.WalkSpeed = origSpeed end
		for d in pairs(noclipParts) do d.CanCollide = true end
	end)
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	conns = {}
end

return Extras
