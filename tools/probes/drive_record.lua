-- Drive recorder: press ; to start, = to stop. Records how YOU drive (position, heading, speed, keys, wheel angle, whether you are on the road,
-- what is ahead) 20 times a second to ScrdsxScript/driverec_latest.csv (+ a timestamped copy). Used to train the autopilot.
-- Run it on its own (not together with the main script). Drive on the road like you normally would, take corners, roundabouts, junctions,
-- and also reverse / turn around / bump into things on purpose when you want the autopilot to learn that.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer
local env = getgenv and getgenv() or _G
if env.DriveRec then pcall(function() env.DriveRec.Destroy() end) end

local START_KEY, STOP_KEY = Enum.KeyCode.Semicolon, Enum.KeyCode.Equals
local HZ = 20

local R = { rows = {}, on = false, t0 = 0, acc = 0, saveT = 0, conns = {}, markN = 0 }
env.DriveRec = R

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return lp:WaitForChild("PlayerGui")
end
local gui = Instance.new("ScreenGui")
gui.Name = tostring(math.random(1e6, 9e6)); gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 999
gui.Parent = guiParent()
local lbl = Instance.new("TextLabel")
lbl.AnchorPoint = Vector2.new(.5, 0); lbl.Position = UDim2.new(.5, 0, 0, 16); lbl.Size = UDim2.fromOffset(0, 30); lbl.AutomaticSize = Enum.AutomaticSize.X
lbl.BackgroundColor3 = Color3.fromRGB(10, 10, 12); lbl.BackgroundTransparency = .15; lbl.TextColor3 = Color3.new(1, 1, 1)
lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 14; lbl.BorderSizePixel = 0; lbl.Parent = gui
Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)
local pad = Instance.new("UIPadding", lbl); pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14)
local function say(t, color) lbl.Text = t; lbl.TextColor3 = color or Color3.new(1, 1, 1) end
say("Drive recorder: ; = start,  = = stop")

local HEADER = "t,x,y,z,yawDeg,vx,vz,speed,fwdSpeed,throttleAttr,steerAttr,keyW,keyS,keyA,keyD,wheelDeg,health,onRoad,road,dangerDist,dangerName"
local roadParams = RaycastParams.new()
roadParams.FilterType = Enum.RaycastFilterType.Include
roadParams.FilterDescendantsInstances = workspace:FindFirstChild("Roads") and { workspace.Roads } or {}

local function save(final)
	pcall(function()
		if not writefile then return end
		pcall(function() if makefolder then makefolder("ScrdsxScript") end end)
		local text = HEADER .. "\n" .. table.concat(R.rows, "\n") .. "\n"
		writefile("ScrdsxScript/driverec_latest.csv", text)
		if final then writefile(("ScrdsxScript/driverec_%d.csv"):format(os.time()), text) end
	end)
end

local function sample()
	local car = workspace:FindFirstChild("Vehicles") and workspace.Vehicles:FindFirstChild(lp.Name)
	local seat = car and car:FindFirstChild("DriveSeat")
	if not seat then return end
	local pos, v, look = seat.Position, seat.AssemblyLinearVelocity, seat.CFrame.LookVector
	local fwd = Vector3.new(look.X, 0, look.Z)
	fwd = fwd.Magnitude > 0.01 and fwd.Unit or Vector3.new(0, 0, -1)
	local yaw = math.deg(math.atan2(fwd.X, fwd.Z))
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local fs = v.X * fwd.X + v.Z * fwd.Z
	local wheel = 0
	pcall(function() wheel = seat.TopAttachmentFL.Orientation.Y end)
	local onRoad, road = 0, ""
	pcall(function()
		local res = workspace:Raycast(Vector3.new(pos.X, pos.Y + 40, pos.Z), Vector3.new(0, -160, 0), roadParams)
		if res and res.Instance.Name:find("Road", 1, true) then
			onRoad = 1
			road = res.Instance.Parent and res.Instance.Parent.Name or ""
		end
	end)
	local dd, dn = "", ""
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { lp.Character, car, workspace:FindFirstChild("Vehicles") }
		local origin = Vector3.new(pos.X, pos.Y - 0.5, pos.Z) + fwd * 3
		local r = workspace:Blockcast(CFrame.lookAt(origin, origin + fwd), Vector3.new(6, 3, 1), fwd * 40, params)
		if r and r.Instance ~= workspace.Terrain then dd = ("%.1f"):format(r.Distance); dn = r.Instance.Name end
	end)
	R.rows[#R.rows + 1] = ("%.3f,%.2f,%.2f,%.2f,%.1f,%.2f,%.2f,%.2f,%.2f,%s,%s,%d,%d,%d,%d,%.2f,%s,%d,%s,%s,%s"):format(
		os.clock() - R.t0, pos.X, pos.Y, pos.Z, yaw, v.X, v.Z, speed, fs,
		tostring(car:GetAttribute("Throttle") or 0), tostring(car:GetAttribute("Steering") or 0),
		UIS:IsKeyDown(Enum.KeyCode.W) and 1 or 0, UIS:IsKeyDown(Enum.KeyCode.S) and 1 or 0,
		UIS:IsKeyDown(Enum.KeyCode.A) and 1 or 0, UIS:IsKeyDown(Enum.KeyCode.D) and 1 or 0,
		wheel, tostring(car:GetAttribute("currentHealth") or ""), onRoad, road, dd, dn)
end

local function start()
	if R.on then return end
	R.rows, R.on, R.t0, R.acc, R.saveT = {}, true, os.clock(), 0, os.clock()
	say("● RECORDING   (= to stop)", Color3.fromRGB(255, 90, 90))
end
local function stop()
	if not R.on then return end
	R.on = false
	save(true)
	say(("Saved %d samples (%.0f s) to ScrdsxScript/driverec_latest.csv"):format(#R.rows, os.clock() - R.t0), Color3.fromRGB(120, 230, 150))
end
R.Start, R.Stop = start, stop

table.insert(R.conns, UIS.InputBegan:Connect(function(i)
	if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() then return end
	if i.KeyCode == START_KEY then start() elseif i.KeyCode == STOP_KEY then stop() end
end))
table.insert(R.conns, RunService.Heartbeat:Connect(function(dt)
	if not R.on then return end
	R.acc = R.acc + dt
	if R.acc >= 1 / HZ then
		R.acc = 0
		pcall(sample)
		if os.clock() - R.saveT > 10 then R.saveT = os.clock(); save(false) end
		lbl.Text = ("● RECORDING  %d s   (= to stop)"):format(os.clock() - R.t0)
	end
end))

function R.Destroy()
	R.on = false
	for _, c in ipairs(R.conns) do pcall(function() c:Disconnect() end) end
	pcall(function() gui:Destroy() end)
	env.DriveRec = nil
end
