-- AutoFarm: robs the stores for you. Built from tools/farm_probe.lua + tools/farm_record.lua (what the game really sends).
--   cash registers : punch the register until it breaks, pick up the money drops
--   bank           : buy a bomb at the nearest dealer, throw it at the vault door, collect all money + gold, sell the gold
--   jeweler / club : (EXPERIMENTAL) bomb the safe(s), collect what is inside
-- Movement: the car (Teleports module) takes you near the place, then you move on foot with noclip + velocity (no CFrame jumps).
-- UNTESTED in game. The remote ids below were read from the recording; if the game updates they must be re-read.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CS = game:GetService("CollectionService")
local lp = Players.LocalPlayer
local V3 = Vector3.new

local ID = {
	INTERACT = "e3256932-2913-480f-93e8-9cda8c896b14", -- (target, actionId, "start" | "stop" | "cancel")
	BUY = "1c8bfd0c-2399-477f-8eac-fec0ba502317",      -- ("Bomb", "Dealer")
	SELL = "eee773c0-a099-46cc-b27c-44f7c84c0324",     -- ("Gold", "Dealer")
	EQUIP = "910a8b37-75ee-42aa-897a-ad920fa54120",    -- ("Bomb")  equips that item (the game's inventoryController.equipTool)
	UNEQUIP = "22bad4a5-9dc6-4362-ab06-c24b29951bfd",  -- ()  puts the item away = hands (inventoryController.unequipTool)
	THROW = "78362192-b9dc-4744-9e59-0d72a5b791cf",    -- (tool, x, y, z)  throws the bomb in an arc to that point
	DETONATE = "d1152c57-eaab-4cb4-8861-404a5640d434", -- ()  blows up the bombs you threw (inventoryController.detonateBombs)
	PUNCH = "cc21144d-23ac-4754-8144-1a3f985e016a",    -- ()  one swing, ~6 damage to a register in reach
}
local ACT = { dealer = "Omm", money = "2vd", item = "7Rm", drop = "P11" }

-- places (from the probes / recording)
local BANK = { pos = V3(-1242, 9, 3115), stand = V3(-1245, 8, 3148), target = V3(-1242.52, 10.58, 3140.02) }
local JEWELER_POS = V3(-412, 12, 3582)
local CLUB_POS = V3(-1744, 11, 3009)
local REGISTERS = { -- robbery folder name -> fallback position
	{ key = "Tool Shop", folder = "Tool Shop Robbery", pos = V3(-759, 9, 635) },
	{ key = "Ares Fuel Station", folder = "Ares Fuel Station Robbery", pos = V3(-839, 7, 1530) },
	{ key = "Gas-N-Go", folder = "Gas-N-Go Fuel Station Robbery", pos = V3(-1541, 9, 3771) },
	{ key = "Osso", folder = "Osso Fuel Station Robbery", pos = nil },
	{ key = "Farm Shop", folder = "Farm Shop Robbery", pos = nil },
	{ key = "Clothing Store", folder = "Clothing Store Robbery", pos = nil },
}

local Farm = {
	Enabled = false, Busy = false, Cancel = false,
	Registers = true, Bank = true, Jeweler = false, Club = false,
	SellGold = true, SellCalls = 1, WalkSpeed = 60, TravelSpeed = 130, InstantMove = false, Parallel = true, bombs = 0, SitInteract = false, Manual = false, AutoDrive = true, DriveSpeed = 80, ManualRange = 250,
	Info = "off", Stats = "-", Tele = nil,
	cool = {}, done = { registers = 0, bank = 0, jeweler = 0, club = 0, fails = 0 },
}

local T0 = os.clock()
local logbuf = {}
local function posStr()
	local c = lp.Character
	local h = c and c:FindFirstChild("HumanoidRootPart")
	return h and ("(%.0f,%.0f,%.0f)"):format(h.Position.X, h.Position.Y, h.Position.Z) or "(no char)"
end
local writing = false
local function flush()
	if writing then return end
	writing = true
	task.delay(0.4, function()
		writing = false
		pcall(function() if writefile then writefile("farm_log.txt", table.concat(logbuf, string.char(10))) end end)
	end)
end
local function flog(s)
	logbuf[#logbuf + 1] = ("[+%6.1f] %s  @%s"):format(os.clock() - T0, s, posStr())
	if #logbuf > 400 then table.remove(logbuf, 1) end
	flush() -- written to farm_log.txt as it happens, so a game crash does not lose it
end
function Farm.Trace(msg) flog("  tele: " .. msg) end
function Farm.CopyLog()
	local txt = table.concat(logbuf, "\n")
	local ok = pcall(function() setclipboard(txt) end)
	pcall(function() writefile("farm_log.txt", txt) end)
	return ok
end
local function changed() if Farm.Changed then task.defer(Farm.Changed) end end
local function say(s) Farm.Info = s; flog(s); changed() end
local startMoney
local function stats()
	local d = Farm.done
	local m = Farm.moneyNow and Farm.moneyNow()
	if m and not startMoney then startMoney = m end
	Farm.Stats = ("reg %d  bank %d  jewel %d  club %d  fails %d%s"):format(d.registers, d.bank, d.jeweler, d.club, d.fails,
		(m and startMoney) and ("  +" .. math.floor(m - startMoney) .. " EUR") or "")
end

-- remotes -------------------------------------------------------------------------------------------------
local cache = {}
local function remote(id)
	local r = cache[id]
	if r and r.Parent then return r end
	local folder = RS:FindFirstChild("mBd")
	r = folder and folder:FindFirstChild(id)
	if not r then
		for _, d in ipairs(RS:GetDescendants()) do
			if d.Name == id then r = d; break end
		end
	end
	cache[id] = r
	return r
end
local function fire(id, ...)
	local r = remote(id)
	if not r then return false end
	r:FireServer(...)
	return true
end

-- helpers ---------------------------------------------------------------------------------------------------------
local function parts()
	local c = lp.Character
	return c, c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
end
local function where(inst)
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then
		local ok, cf = pcall(function() return inst:GetBoundingBox() end)
		if ok then return cf.Position end
	end
	local sum, n = V3(), 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then sum = sum + d.Position; n = n + 1 end
	end
	return n > 0 and sum / n or nil
end
local function ready(key) return (Farm.cool[key] or 0) <= os.clock() end
local function cooldown(key, s) Farm.cool[key] = os.clock() + s end

local function stream(pos) pcall(function() lp:RequestStreamAroundAsync(pos, 8) end) end

-- on foot: small CFrame steps every frame (about walking speed x2), noclip while moving, always restored afterwards
local function restoreChar()
	local c, hum, hrp = parts()
	pcall(function()
		if hum then
			hum.PlatformStand = false
			if hum.Health > 0 and hum:GetState() == Enum.HumanoidStateType.Physics then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
		end
		if hrp then
			hrp.AssemblyLinearVelocity = V3()
			hrp.AssemblyAngularVelocity = V3()
			local look = hrp.CFrame.LookVector
			local flat = V3(look.X, 0, look.Z)
			if flat.Magnitude > 0.05 then hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat.Unit) end
		end
	end)
end
-- Walk like a player: pathfinding + Humanoid:MoveTo with collisions ON. (Noclip walking was rejected by the server: it put
-- you back where you had been standing, see the farm log.) Speed is the Humanoid's own walk speed.
local PFS = game:GetService("PathfindingService")
local function near(p, target, r)
	local dx, dz = p.X - target.X, p.Z - target.Z
	return math.sqrt(dx * dx + dz * dz) <= r and math.abs(p.Y - target.Y) < 9
end
local function moveStep(hum, hrp, target, timeout, r)
	hum:MoveTo(target)
	local t, lastPos, lastT, tries = os.clock(), hrp.Position, os.clock(), 0
	while os.clock() - t < timeout and not Farm.Cancel and hrp.Parent do
		task.wait(0.1)
		if near(hrp.Position, target, r) then return true end
		if os.clock() - lastT > 0.9 then
			if (hrp.Position - lastPos).Magnitude < 1.5 then
				tries = tries + 1
				hum.Jump = true
				if tries % 2 == 0 then
					-- blocked: step sideways, alternating left / right, then try again
					local d = target - hrp.Position
					d = V3(d.X, 0, d.Z)
					if d.Magnitude > 1 then
						local side = V3(-d.Z, 0, d.X).Unit * ((tries % 4 == 0) and -9 or 9)
						hum:MoveTo(hrp.Position + side)
						task.wait(0.9)
					end
				end
			end
			lastPos, lastT = hrp.Position, os.clock()
			hum:MoveTo(target)
		end
	end
	return near(hrp.Position, target, r)
end
local function walkTo(pos, _, stop, maxLen)
	local _, hum, hrp = parts()
	if not (hum and hrp) or hum.Health <= 0 then return false end
	stop = stop or 3
	if hum.SeatPart then hum.Sit = false; task.wait(0.4) end
	if Farm.InstantMove then
		-- instant teleport on foot; if the server puts you back, fall through to real walking
		local from = hrp.Position
		hrp.CFrame = CFrame.new(pos + V3(0, 2, 0)) * hrp.CFrame.Rotation
		hrp.AssemblyLinearVelocity = V3()
		task.wait(0.35)
		local now = hrp.Position
		if near(now, pos, stop + 4) then return true end
		flog(("instant move was reverted (now %.0f studs from the target), walking instead"):format((now - pos).Magnitude))
		if (now - from).Magnitude < 6 then Farm.InstantMove = false; flog("instant move switched off for this session") end
	end
	local waypoints
	local path = PFS:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 5 })
	local okc = pcall(function() path:ComputeAsync(hrp.Position, pos) end)
	if okc and path.Status == Enum.PathStatus.Success then
		waypoints = path:GetWaypoints()
	else
		-- closed doors are walls for the path finder. Plan again with every unlocked door treated as open (only for the planning,
		-- they are solid again right after): the route then leads through the doors, and walking into a door opens it.
		local saved = {}
		pcall(function()
			for _, tag in ipairs({ "Sliding Door", "Hinge Door" }) do
				for _, d in ipairs(CS:GetTagged(tag)) do
					local dp = d:IsA("Model") and d:GetPivot().Position or (d:IsA("BasePart") and d.Position)
					if dp and d:GetAttribute("Locked") ~= true and ((dp - hrp.Position).Magnitude < 400 or (dp - pos).Magnitude < 400) then
						for _, bp in ipairs(d:GetDescendants()) do
							if bp:IsA("BasePart") and bp.CanCollide then saved[#saved + 1] = bp; bp.CanCollide = false end
						end
					end
				end
			end
		end)
		local pd = PFS:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 5 })
		local okd = pcall(function() pd:ComputeAsync(hrp.Position, pos) end)
		local gotD = okd and pd.Status == Enum.PathStatus.Success
		if not gotD then -- the target itself may be inside something: try spots around it, still with the doors open
			for _, off in ipairs({ V3(4, 0, 0), V3(-4, 0, 0), V3(0, 0, 4), V3(0, 0, -4), V3(8, 0, 0), V3(-8, 0, 0), V3(0, 0, 8), V3(0, 0, -8) }) do
				local alt = PFS:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 5 })
				if pcall(function() alt:ComputeAsync(hrp.Position, pos + off) end) and alt.Status == Enum.PathStatus.Success then pd, gotD = alt, true; break end
			end
		end
		for _, bp in ipairs(saved) do pcall(function() bp.CanCollide = true end) end
		if gotD then
			waypoints = pd:GetWaypoints()
			waypoints[#waypoints + 1] = { Position = pos, Action = Enum.PathWaypointAction.Walk }
			flog(("path found through the doors (%d door parts treated as open for planning)"):format(#saved))
		end
	end
	if not waypoints then
		local why = okc and tostring(path.Status) or "error"
		-- the destination may be inside something solid: try spots around it
		for _, off in ipairs({ V3(4, 0, 0), V3(-4, 0, 0), V3(0, 0, 4), V3(0, 0, -4), V3(8, 0, 0), V3(-8, 0, 0), V3(0, 0, 8), V3(0, 0, -8) }) do
			local alt = PFS:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 5 })
			local ok2 = pcall(function() alt:ComputeAsync(hrp.Position, pos + off) end)
			if ok2 and alt.Status == Enum.PathStatus.Success then
				waypoints = alt:GetWaypoints()
				waypoints[#waypoints + 1] = { Position = pos, Action = Enum.PathWaypointAction.Walk }
				flog("path found to a spot next to the target (" .. why .. " for the exact point)")
				break
			end
		end
		if not waypoints then
			flog("no path (" .. why .. "), walking straight")
			waypoints = { { Position = pos, Action = Enum.PathWaypointAction.Walk } }
		end
	end
	-- how far is the walk really? (a dealer behind a fence can mean a 300 stud detour)
	local plen, prev = 0, hrp.Position
	for _, wp in ipairs(waypoints) do plen = plen + (wp.Position - prev).Magnitude; prev = wp.Position end
	local straight = (hrp.Position - pos).Magnitude
	flog(("walk: %d waypoints, %.0f studs to walk (straight line %.0f)"):format(#waypoints, plen, straight))
	if maxLen and plen > maxLen then
		flog(("walk: too far to walk (%.0f > %d), not going"):format(plen, maxLen))
		return false, "toolong"
	end
	if Farm.Cancel then flog("walk skipped: the farm was cancelled"); return false end
	local t0 = os.clock()
	local budget = plen / 14 + 8
	for _, wp in ipairs(waypoints) do
		if Farm.Cancel or os.clock() - t0 > budget then break end
		if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
		moveStep(hum, hrp, wp.Position, 4, 3)
	end
	if not near(hrp.Position, pos, stop) and os.clock() - t0 < budget + 5 then moveStep(hum, hrp, pos, 5, stop) end
	local ok = near(hrp.Position, pos, stop + 1.5)
	flog(("walk: %s after %.1fs, %.1f studs from the target"):format(ok and "arrived" or "did NOT arrive", os.clock() - t0, (hrp.Position - pos).Magnitude))
	return ok
end
-- a real left click (what the game's own punch code reacts to), used when the bare punch message does not do damage
local VIM = game:GetService("VirtualInputManager")
local function realClick()
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize or V3(1920, 1080, 0)
	local x, y = v.X * 0.3, v.Y * 0.45 -- left-centre: away from the menu (right) and the HUD (far left)
	local ok = pcall(function()
		VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
		task.wait(0.06)
		VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
	end)
	if not ok and mouse1click then pcall(mouse1click) end
end
-- the game punches with the F key (recorded with tools/punch_probe.lua): its own handler plays the swing animation first and
-- only then tells the server, and the server only damages things for a real swing. Sending the bare message did nothing.
local function punch()
	local ok = pcall(function()
		VIM:SendKeyEvent(true, Enum.KeyCode.F, false, game)
		task.wait(0.06)
		VIM:SendKeyEvent(false, Enum.KeyCode.F, false, game)
	end)
	if not ok then fire(ID.PUNCH) end
end
local function playerState()
	local c, hum, hrp = parts()
	local tracks = 0
	pcall(function() tracks = #hum:FindFirstChildOfClass("Animator"):GetPlayingAnimationTracks() end)
	local tools = {}
	for _, ch in ipairs(c and c:GetChildren() or {}) do if ch:IsA("Tool") then tools[#tools + 1] = ch.Name end end
	return ("state=%s visible=%s seatPart=%s tools=[%s] anims=%d"):format(tostring(hum and hum:GetState()), tostring(c and c:GetAttribute("Visible")),
		tostring(hum and hum.SeatPart), table.concat(tools, ","), tracks)
end

local function face(pos)
	local _, _, hrp = parts()
	if hrp then hrp.CFrame = CFrame.lookAt(hrp.Position, V3(pos.X, hrp.Position.Y, pos.Z)) end
end

local function myCar()
	local v = workspace:FindFirstChild("Vehicles")
	local car = v and v:FindFirstChild(lp.Name)
	return car, car and car:FindFirstChild("DriveSeat")
end

local hasBomb -- defined further down
-- Get into the car the way the game does it: walk up to it, then send the seat interaction ("B6W", stop). The SERVER seats you if
-- you stand within 10 studs of the seat (see driveSeatInteractable). Jumping your body into the seat with a CFrame is what made
-- the server drag you back afterwards.
local function ensureInCar()
	local _, seat = myCar()
	if not seat then say("spawn your car first"); return false end
	local _, hum, hrp = parts()
	if not (hum and hrp) then return false end
	if hum.SeatPart == seat then return true end
	if not Farm.SitInteract then
		-- the direct way (short hop into the seat): walk next to the car first
		if (hrp.Position - seat.Position).Magnitude > 7 then say("walking to the car"); walkTo(seat.Position, nil, 5) end
		local Tele = Farm.Tele
		local prev = Tele.SitInteract
		Tele.SitInteract = false
		Tele.GoToCar()
		task.wait(0.4)
		while Tele.Busy and not Farm.Cancel do task.wait(0.2) end
		Tele.SitInteract = prev
		task.wait(0.7)
		return hum.SeatPart == seat
	end
	for attempt = 1, 3 do
		if (hrp.Position - seat.Position).Magnitude > 7 then
			say("walking to the car")
			walkTo(seat.Position, nil, 5)
		end
		fire(ID.INTERACT, seat, "B6W", "stop")
		local t = os.clock()
		while os.clock() - t < 2.2 and hum.SeatPart ~= seat do task.wait(0.1) end
		if hum.SeatPart == seat then
			task.wait(0.7) -- let the server finish seating you before the car moves
			return true
		end
		flog(("the seat interaction did not seat us (try %d), distance %.1f"):format(attempt, (hrp.Position - seat.Position).Magnitude))
		hum.Sit = false
	end
	return false
end
-- is there a bomb in the inventory?  (reads the game's own player data, no stepping out of the car)
local function bombCheck()
	return hasBomb()
end

-- drive (Teleports module) to a place and step out of the car
local function leaveCar()
	local _, hum = parts()
	if hum and hum.SeatPart then
		hum.Sit = false
		task.wait(0.35)
		if hum.SeatPart then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end); task.wait(0.4) end
	end
	local c = parts()
	if c and c:GetAttribute("Visible") == false then
		local t = os.clock()
		while c:GetAttribute("Visible") == false and os.clock() - t < 3 do task.wait(0.1) end
	end
	task.wait(0.5)
end

local function goNear(pos, name)
	local Tele = Farm.Tele
	if Farm.AutoDrive and not Farm.Manual then
		-- the real thing: drive the car with throttle + steering along the game's roads (the server accepts that)
		local prevSit = Farm.SitInteract
		Farm.SitInteract = true -- sit the legitimate way, the server then knows you are in the car
		local seated = ensureInCar()
		Farm.SitInteract = prevSit
		if not seated then say("could not get into the car"); return false end
		say("driving to " .. name)
		Farm.Drive.MaxSpeed = Farm.DriveSpeed
		local ok, why
		local replans, reroutes = 0, 0
		for attempt = 1, 9 do
			ok, why = Farm.Drive.To(pos, { arrive = 22, name = name, replans = replans, reroutes = reroutes })
			flog(("autopilot result: %s (%s)"):format(tostring(ok), tostring(why)))
			if ok or Farm.Cancel or (why ~= "left the car" and why ~= "stuck" and why ~= "replan" and why ~= "reroute") then break end
			if why == "reroute" then reroutes = reroutes + 1 elseif why == "replan" then replans = math.min(replans + 1, 4) end
			say((why == "replan" or why == "reroute") and "taking another route" or "lost the car, getting back in and driving on")
			if why ~= "reroute" then
				Farm.SitInteract = true
				ensureInCar()
				Farm.SitInteract = prevSit
			end
		end
		if not ok then say("could not drive to " .. name .. ": " .. tostring(why)); return false end
		leaveCar()
		return true
	end	if Farm.Manual then
		-- the automatic car trips are not accepted by the server (it only keeps ~1 s of a scripted flight), so YOU drive to the area
		local _, hum0, hrp0 = parts()
		local dist = hrp0 and (hrp0.Position - pos).Magnitude or 1e9
		if dist > Farm.ManualRange then
			say(("%s is %.0f studs away: drive there yourself, then press the button again"):format(name, dist))
			return false
		end
		if hum0 and hum0.SeatPart then hum0.Sit = false; task.wait(0.7) end
		return true
	end
	ensureInCar()
	say("driving to " .. name)
	stream(pos)
	Tele.SitInteract = Farm.SitInteract -- the trip must judge "seated" the same way the car was entered
	-- farm trips are slower and gentler than the Teleports tab: the server drops you out of the car on fast / long ones
	-- stay low and slow, like a real car: the server threw you out of the seat ~1.3 s after takeoff at 220 st/s and 50 studs up
	local oldMax, oldAccel, oldLift, oldH, oldG = Tele.FlyMaxSpeed, Tele.Accel, Tele.FlyMinLift, Tele.Height, Tele.GroundFollow
	Tele.FlyMaxSpeed, Tele.Accel, Tele.FlyMinLift, Tele.Height, Tele.GroundFollow = Farm.TravelSpeed, 150, 4, 4, true
	Tele.GoTo({ name = name, pos = pos })
	task.wait(0.4)
	while (Tele.Busy or Tele.Chain) and not Farm.Cancel do task.wait(0.2) end
	Tele.FlyMaxSpeed, Tele.Accel, Tele.FlyMinLift, Tele.Height, Tele.GroundFollow = oldMax, oldAccel, oldLift, oldH, oldG
	if tostring(Tele.Info):find("setback") then
		flog("SETBACK: stopping the farm so nothing else goes wrong")
		Farm.Stop()
		say("stopped: the server moved you out of the car. Try again from a standing start (Travel speed lower)")
		if Farm.Stopped then task.defer(Farm.Stopped) end
		return false
	end
	if Farm.Cancel then return false end
	flog(("teleport result=%s info=%s"):format(tostring(Tele.LastResult), tostring(Tele.Info)))
	if Tele.LastResult ~= "ok" then say("could not drive to " .. name .. ": " .. tostring(Tele.Info)); return false end
	local car, seat = myCar()
	if not seat or (seat.Position - pos).Magnitude > 250 then say("the car is not at " .. name); return false end
	local _, hum, hrp = parts()
	-- thrown out during the trip? sit back in before doing anything else
	if hum and (hum.SeatPart ~= seat or (hrp.Position - seat.Position).Magnitude > 15) then
		flog(("not in the car after the trip (%.0f studs away), sitting back in"):format(hrp and (hrp.Position - seat.Position).Magnitude or -1))
		Tele.GoToCar()
		task.wait(0.3)
		while Tele.Busy and not Farm.Cancel do task.wait(0.2) end
		_, hum, hrp = parts()
	end
	if hum and hum.SeatPart then
		hum.Sit = false
		task.wait(0.35)
		if hum.SeatPart then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end); task.wait(0.4) end
	end
	task.wait(1.2)
	local _, _, h3 = parts()
	local _, seat3 = myCar()
	if h3 and seat3 and (h3.Position - seat3.Position).Magnitude > 45 then
		flog(("DESYNC: after getting out you are %.0f studs from the car (the server had a different position for it)"):format((h3.Position - seat3.Position).Magnitude))
		say("the server lost the car during the trip (you were moved back). Stopped; try a shorter trip")
		Farm.Stop()
		if Farm.Stopped then task.defer(Farm.Stopped) end
		return false
	end
	-- the server shows "Visible" again once it knows you are out of the car
	local c = parts()
	if c and c:GetAttribute("Visible") == false then
		local t = os.clock()
		while c:GetAttribute("Visible") == false and os.clock() - t < 3 do task.wait(0.1) end
		flog("out of the car, Visible=" .. tostring(c:GetAttribute("Visible")))
	end
	return true
end
local function backToCar()
	local _, seat = myCar()
	if not seat then return false end
	say("back to the car")
	ensureInCar()
	return true
end

-- interactions ----------------------------------------------------------------------------------------------
local function holdInteract(part, id, hold)
	fire(ID.INTERACT, part, id, "start")
	local t = os.clock()
	while os.clock() - t < (hold or 2.6) do
		if Farm.Cancel then fire(ID.INTERACT, part, id, "cancel"); return false end
		task.wait(0.1)
	end
	fire(ID.INTERACT, part, id, "stop")
	return true
end

-- hold several pickups at the same time (they all take the same ~2.5 s): start them all, wait, stop them all
local function holdBatch(items, hold)
	for _, it in ipairs(items) do fire(ID.INTERACT, it.part, it.id, "start") end
	local t = os.clock()
	while os.clock() - t < (hold or 2.52) do
		if Farm.Cancel then
			for _, it in ipairs(items) do fire(ID.INTERACT, it.part, it.id, "cancel") end
			return false
		end
		task.wait(0.1)
	end
	for _, it in ipairs(items) do fire(ID.INTERACT, it.part, it.id, "stop") end
	return true
end
-- the first item plus every other one within 8 studs of it (max 4)
local function batchAround(list, first)
	local batch = { first }
	local _, _, hrp = parts()
	local here = hrp and hrp.Position or first.part.Position
	if Farm.Parallel then
		for _, o in ipairs(list) do
			if o ~= first and #batch < 6 and (o.part.Position - here).Magnitude < 12 then batch[#batch + 1] = o end
		end
	end
	return batch
end
local function afterBatch(batch, tried)
	local got = 0
	for _, it in ipairs(batch) do
		if not it.part.Parent or it.part:GetAttribute("Enabled") ~= true then got = got + 1 else tried[it.part] = (tried[it.part] or 0) + 1 end
	end
	if #batch > 1 and got == 0 and Farm.Parallel then
		Farm.Parallel = false
		flog("picking up several at once did not work, one at a time from now on")
	end
	return got
end

-- pick up everything under `root' that is switched on (money = id 2vd, items/gold = id 7Rm)
local function loot(root, label)
	local tried, got = {}, 0
	local lastHere
	while not Farm.Cancel do
		local list = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("Enabled") == true and d:GetAttribute("Collectable") ~= false and (tried[d] or 0) < 3 then
				local money = CS:HasTag(d, "Money Collect Interactable")
				local item = CS:HasTag(d, "Item Collect Interactable")
				if money or item then list[#list + 1] = { part = d, id = money and ACT.money or ACT.item } end
			end
		end
		if #list == 0 then break end
		local _, _, hrp = parts()
		if not hrp then break end
		local here = hrp.Position
		if lastHere and (here - lastHere).Magnitude > 250 then
			flog(("%s: the character was moved %.0f studs in a moment (arrested?): stopping the loot run"):format(label, (here - lastHere).Magnitude))
			break
		end
		lastHere = here
		table.sort(list, function(a, b) return (a.part.Position - here).Magnitude < (b.part.Position - here).Magnitude end)
		local it = list[1]
		walkTo(it.part.Position + V3(0, 1.5, 0), Farm.WalkSpeed, 2.5)
		local batch = batchAround(list, it)
		say(("%s: collecting %d left (%d at once)"):format(label, #list, #batch))
		holdBatch(batch)
		task.wait(0.15)
		got = got + afterBatch(batch, tried)
	end
	return got
end

-- Bombs are not tools in your backpack until you equip them, so the only way to know is to try: send the equip message and see
-- whether a Bomb appears in your hand (only works on foot), then put it away again. Takes about 2 seconds.
-- The game keeps your inventory / money in a client-side state store (Code.producer -> playerData). Read it directly.
local function playerData()
	local ok, pd = pcall(function() return require(lp.PlayerScripts.Code.producer).producer:getState().playerData end)
	return (ok and type(pd) == "table") and pd or nil
end
local function bombCount()
	local pd = playerData()
	if not pd or type(pd.inventory) ~= "table" then return nil end
	local n = 0
	for _, list in pairs(pd.inventory) do
		if type(list) == "table" then
			for _, it in pairs(list) do
				if type(it) == "table" and it.name == "Bomb" then n = n + (tonumber(it.count) or 1) end
			end
		end
	end
	return n
end
Farm.moneyNow = function() local pd = playerData(); return pd and tonumber(pd.money) or nil end
function hasBomb()
	local n = bombCount()
	if n ~= nil then
		flog("inventory: " .. n .. " bomb(s)")
		return n > 0
	end
	-- state store not reachable: test by equipping (only works on foot)
	local c = lp.Character
	if not c then return false end
	if c:FindFirstChild("Bomb") then return true end
	fire(ID.EQUIP, "Bomb")
	local t = os.clock()
	while os.clock() - t < 1.6 do
		if c:FindFirstChild("Bomb") then break end
		task.wait(0.1)
	end
	local have = c:FindFirstChild("Bomb") ~= nil
	if have then fire(ID.UNEQUIP); task.wait(0.5) end
	flog("bomb check by equipping: " .. tostring(have))
	return have
end

-- nearest dealer that is loaded (they move around the map)
local function findDealer(skip)
	local _, _, hrp = parts()
	local here = hrp and hrp.Position or V3()
	local best, bd
	local root = workspace:FindFirstChild("Spawned") and workspace.Spawned:FindFirstChild("Dealer")
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if d:IsA("BasePart") and d:GetAttribute("ItemStore") == "Dealer" and not (skip and skip[d]) then
			local dist = (d.Position - here).Magnitude
			if not bd or dist < bd then best, bd = d, dist end
		end
	end
	return best
end

-- go to the nearest dealer and run `fn(dealerPart)` while standing next to it
local function atDealer(fn)
	local skip = {}
	for attempt = 1, 3 do
		local d = findDealer(skip)
		if not d then say("no dealer is loaded nearby"); return false end
		skip[d] = true
		flog(("dealer %d: at (%.0f,%.0f,%.0f)"):format(attempt, d.Position.X, d.Position.Y, d.Position.Z))
		if not goNear(d.Position, "dealer") then return false end
		local ok, why = walkTo(d.Position + V3(0, 1, 0), nil, 3, 160)
		if ok then
			fire(ID.INTERACT, d, ACT.dealer, "stop") -- opens the shop
			task.wait(0.4)
			local res = fn(d)
			fire(ID.INTERACT, d, ACT.dealer, "cancel")
			return res
		end
		if why == "toolong" then
			say("that dealer is behind something (long walk), trying another one")
			ensureInCar()
		else
			say("could not walk to the dealer")
			return false
		end
	end
	return false
end
local function buyBombs(n)
	say("buying " .. n .. " bomb(s)")
	local ok = atDealer(function()
		for i = 1, n do
			if Farm.Cancel then return false end
			fire(ID.BUY, "Bomb", "Dealer")
			Farm.bombs = Farm.bombs + 1
			flog("bought a bomb (counting " .. Farm.bombs .. ")")
			task.wait(0.9)
		end
		return true
	end)
	return ok
end
local function sellGold()
	if not Farm.SellGold then return end
	say("selling gold")
	atDealer(function()
		for _ = 1, Farm.SellCalls do
			fire(ID.SELL, "Gold", "Dealer")
			task.wait(0.8)
		end
		return true
	end)
end

-- equip the bomb and throw it at `target` from where you stand
local function throwBomb(target)
	local c, hum = parts()
	if not c then return false end
	local tool = c:FindFirstChild("Bomb")
	if not tool then
		fire(ID.EQUIP, "Bomb") -- the equip message toggles, so only send it when the bomb is not already in your hand
		local t = os.clock()
		while os.clock() - t < 2.5 do
			tool = c:FindFirstChild("Bomb")
			if tool then break end
			task.wait(0.1)
		end
	end
	if not tool then
		flog("equipping the bomb failed: no bomb in the inventory")
		return false
	end
	task.wait(0.8)
	local before = bombCount()
	fire(ID.THROW, tool, target.X, target.Y, target.Z)
	task.wait(0.4)
	if before then
		local function now() return bombCount() or before end
		local t = os.clock()
		while os.clock() - t < 2.5 and now() >= before do task.wait(0.15) end
		if now() >= before then
			flog("the bomb count did not go down after the throw: throwing again")
			fire(ID.THROW, tool, target.X, target.Y + 0.5, target.Z)
			task.wait(0.4)
			t = os.clock()
			while os.clock() - t < 2.5 and now() >= before do task.wait(0.15) end
			if now() >= before then flog("throw failed: the bomb is still in the inventory"); return false end
		end
		flog(("bomb thrown (inventory %d -> %d)"):format(before, now()))
	end
	return true
end
local function waitAttr(inst, name, want, seconds)
	local t = os.clock()
	while os.clock() - t < seconds and not Farm.Cancel do
		if inst and inst.Parent and inst:GetAttribute(name) == want then return true end
		task.wait(0.2)
	end
	return false
end

-- routines ----------------------------------------------------------------------------------------------------------
local function tryRoutine(name, fn)
	local ok, res = pcall(fn)
	if not ok then
		print("[farm] " .. name .. " error: " .. tostring(res))
		flog("ERROR in " .. name .. ": " .. tostring(res))
		restoreChar()
		Farm.CopyLog()
		say(name .. " error: " .. tostring(res):sub(1, 60))
		Farm.done.fails = Farm.done.fails + 1
		cooldown(name, 90)
		return true
	end
	if res == false then Farm.done.fails = Farm.done.fails + 1 end
	stats(); changed()
	return true
end

local function locationFor(entry)
	if entry.pos then return entry.pos end -- coordinates read from Workspace.Robberies
	local Tele = Farm.Tele
	for _, l in ipairs(Tele and Tele.Locations or {}) do
		if l.name:lower():find(entry.key:lower(), 1, true) then return l.pos end
	end
	return nil
end

-- shops are closed boxes with glass walls: find the entrance (a door near the register) and go in through it
local function doorsNear(p, radius)
	local list = {}
	for _, tag in ipairs({ "Sliding Door", "Hinge Door", "Garage Door" }) do
		for _, d in ipairs(CS:GetTagged(tag)) do
			local dp = d:IsA("Model") and d:GetPivot().Position or (d:IsA("BasePart") and d.Position)
			if dp and (dp - p).Magnitude < radius then list[#list + 1] = { inst = d, pos = dp, dist = (dp - p).Magnitude, tag = tag } end
		end
	end
	table.sort(list, function(a, b) return a.dist < b.dist end)
	return list
end
local function doorCentre(inst, fallback)
	local door = inst:FindFirstChild("Door")
	local mp = door and door:FindFirstChild("MainPart")
	return (mp and mp:IsA("BasePart")) and mp.Position or fallback
end
-- Closed doors are walls for the path finder, so "is there a path to the target from here?" tells us whether we are on the right side
-- of the building. Doors are tried one after another (remembered one first); the one after which a path exists is saved.
local DOOR_FILE = "ScrdsxScript/doors.json"
local doorMem, doorLoaded = {}, false
local function loadDoors()
	if doorLoaded then return end
	doorLoaded = true
	pcall(function()
		if isfile and readfile and isfile(DOOR_FILE) then
			local d = game:GetService("HttpService"):JSONDecode(readfile(DOOR_FILE))
			if type(d) == "table" then doorMem = d end
		end
	end)
end
local function saveDoors()
	pcall(function()
		if writefile then
			pcall(function() if makefolder then makefolder("ScrdsxScript") end end)
			writefile(DOOR_FILE, game:GetService("HttpService"):JSONEncode(doorMem))
		end
	end)
end
local function targetKey(rp) return math.floor(rp.X / 20) .. "," .. math.floor(rp.Z / 20) end
local function pathExists(from, to)
	local p = PFS:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 5 })
	local ok = pcall(function() p:ComputeAsync(from, to) end)
	return ok and p.Status == Enum.PathStatus.Success
end
local function enterShop(rp)
	loadDoors()
	local _, _, hrp = parts()
	local flatD = V3(hrp.Position.X - rp.X, 0, hrp.Position.Z - rp.Z).Magnitude
	if flatD < 12 then return true end -- already inside
	if pathExists(hrp.Position, rp) then flog("a walking path to the target exists, no door needed"); return true end
	local mem = doorMem[targetKey(rp)]
	local cands = {}
	for _, d in ipairs(doorsNear(rp, 95)) do
		local n = d.inst.Name:lower()
		local locked = d.inst:GetAttribute("Locked") == true
		local staff = n:find("metal", 1, true) or n:find("staff", 1, true) or n:find("back", 1, true) or n:find("service", 1, true) or n:find("garage", 1, true)
		local centre = doorCentre(d.inst, d.pos)
		local score = d.dist + (locked and 500 or 0) + (staff and 220 or 0) + ((n:find("glass", 1, true) or n:find("sliding", 1, true)) and -20 or 0)
		if mem and (centre - V3(mem.x, mem.y, mem.z)).Magnitude < 4 then score = score - 2000 end -- the door that worked last time
		cands[#cands + 1] = { d = d, centre = centre, score = score, locked = locked, staff = staff ~= nil }
	end
	table.sort(cands, function(a, b) return a.score < b.score end)
	for i = 1, math.min(#cands, 5) do
		local cd = cands[i]
		flog(("door try %d: %s at (%.0f,%.0f,%.0f), score %.0f%s"):format(i, cd.d.inst.Name, cd.centre.X, cd.centre.Y, cd.centre.Z, cd.score,
			(mem and cd.score < -1000) and " (worked last time)" or ""))
		say(("trying door %d/%d: %s"):format(i, math.min(#cands, 5), cd.d.inst.Name))
		local _, _, h = parts()
		local out = V3(h.Position.X - cd.centre.X, 0, h.Position.Z - cd.centre.Z)
		out = out.Magnitude > 0.1 and out.Unit or V3(1, 0, 0)
		walkTo(cd.centre + out * 9 + V3(0, 1, 0), nil, 3)    -- in front of it
		task.wait(0.3)
		walkTo(cd.centre - out * 9 + V3(0, 1, 0), nil, 3)    -- push through it
		task.wait(0.5)
		local _, _, h2 = parts()
		if h2 and pathExists(h2.Position, rp) then
			flog("door worked: there is a walking path to the target from inside")
			doorMem[targetKey(rp)] = { x = cd.centre.X, y = cd.centre.Y, z = cd.centre.Z }
			saveDoors()
			return true
		end
		flog("that door did not lead inside, trying the next one")
	end
	return false
end

local function findRegisterModel(entry)
	local folder = workspace:FindFirstChild("Robberies") and workspace.Robberies:FindFirstChild(entry.folder)
	for _, d in ipairs(folder and folder:GetDescendants() or {}) do
		if d:IsA("Model") and CS:HasTag(d, "Cash Register") then return d end
	end
end

local function robRegister(entry)
	local pos = locationFor(entry)
	if not pos then cooldown(entry.key, 300); return false end
	-- look at the register from here first (streams the area in): a robbed shop is skipped without driving there
	say(entry.key .. ": checking if it is robbed")
	pcall(function() lp:RequestStreamAroundAsync(pos, 8) end)
	local peek = findRegisterModel(entry)
	if peek then
		flog(entry.key .. ": seen from afar, TimedOut=" .. tostring(peek:GetAttribute("TimedOut")))
		if peek:GetAttribute("TimedOut") == true then say(entry.key .. " is on cooldown, skipping it"); cooldown(entry.key, 150); return "skip" end
	else
		flog(entry.key .. ": not visible from afar, will drive there to see")
	end
	if not goNear(pos, entry.key) then cooldown(entry.key, 60); return false end
	local folder = workspace:FindFirstChild("Robberies") and workspace.Robberies:FindFirstChild(entry.folder)
	local model
	for _ = 1, 10 do -- the shop streams in after you arrive
		folder = workspace:FindFirstChild("Robberies") and workspace.Robberies:FindFirstChild(entry.folder)
		for _, d in ipairs(folder and folder:GetDescendants() or {}) do
			if d:IsA("Model") and CS:HasTag(d, "Cash Register") then model = d; break end
		end
		if model then break end
		task.wait(0.5)
	end
	if not model then say(entry.key .. ": register not found"); cooldown(entry.key, 120); return false end
	if model:GetAttribute("TimedOut") == true then say(entry.key .. " is on cooldown, trying the next one"); cooldown(entry.key, 150); backToCar(); return "skip" end
	-- the register itself: the part with the ItemStore attribute (where you press E), else the model's Body
	local body
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("ItemStore") ~= nil then body = d; break end
	end
	body = body or model:FindFirstChild("Body") or model:FindFirstChildWhichIsA("BasePart")
	local rp = body and body.Position or where(model)
	local _, hum, hrp = parts()
	local pl = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then pl[#pl + 1] = ("%s@(%.0f,%.0f,%.0f)"):format(d.Name, d.Position.X, d.Position.Y, d.Position.Z) end
	end
	flog("register parts: " .. table.concat(pl, "; "):sub(1, 420))
	-- is the shop open? log every attribute that could say so (register, shop part, the folder, the doors, the building)
	local function attrs(i)
		local t = {}
		for k, v in pairs(i:GetAttributes()) do t[#t + 1] = k .. "=" .. tostring(v):sub(1, 30) end
		table.sort(t)
		return table.concat(t, ", ")
	end
	flog("shop attrs: model[" .. attrs(model) .. "] folder[" .. attrs(model.Parent) .. "] part[" .. (body and attrs(body) or "") .. "]")
	for i, dd in ipairs(doorsNear(rp, 60)) do
		if i > 2 then break end
		local chain, cur = {}, dd.inst
		for _ = 1, 4 do
			if not cur or cur == workspace then break end
			chain[#chain + 1] = cur.Name .. "[" .. attrs(cur) .. "]"
			cur = cur.Parent
		end
		flog("door chain: " .. table.concat(chain, " < "))
	end
	local lt = game:GetService("Lighting")
	flog(("clock: Lighting.ClockTime=%.2f  workspace attrs[%s]"):format(lt.ClockTime, attrs(workspace)))

	-- Standing spots around the register. The register sits ON a counter, so the old spots 1.6 studs from it were on top of the counter (the
	-- character climbed up there and could not hit anything). Now: points on the FLOOR (same level as where we walked in), nearest first,
	-- spread over different directions. The spot that worked is remembered (ScrdsxScript/stands.json) and tried first next time.
	local rparams = RaycastParams.new()
	rparams.FilterType = Enum.RaycastFilterType.Exclude
	rparams.FilterDescendantsInstances = { lp.Character, (myCar()) }
	local STAND_FILE = "ScrdsxScript/stands.json"
	local standMem = {}
	pcall(function()
		if isfile and readfile and isfile(STAND_FILE) then
			local d = game:GetService("HttpService"):JSONDecode(readfile(STAND_FILE))
			if type(d) == "table" then standMem = d end
		end
	end)
	local sides = {}
	local function buildSides()
		sides = {}
		local _, _, h = parts()
		local floorY = h.Position.Y
		local cand = {}
		for _, r in ipairs({ 2.4, 3.2, 4.0, 5.0, 6.0 }) do
			for k = 0, 15 do
				local ang = k * math.pi / 8
				local x, z = rp.X + math.cos(ang) * r, rp.Z + math.sin(ang) * r
				local res = workspace:Raycast(V3(x, rp.Y + 3, z), V3(0, -12, 0), rparams)
				if res and res.Normal.Y > 0.7 and math.abs(res.Position.Y + 3 - floorY) < 1.4 then
					cand[#cand + 1] = { pos = V3(x, res.Position.Y + 3, z), r = r, a = ang, clear = true }
				end
			end
		end
		table.sort(cand, function(p1, q1) if p1.r ~= q1.r then return p1.r < q1.r end return p1.a < q1.a end)
		for _, cd in ipairs(cand) do
			local okc = true
			for _, d in ipairs(sides) do
				if math.abs((cd.a - d.a + math.pi) % (2 * math.pi) - math.pi) < 1.2 then okc = false; break end
			end
			if okc then sides[#sides + 1] = cd end
			if #sides >= 4 then break end
		end
		local mem = standMem[entry.key]
		if mem then table.insert(sides, 1, { pos = V3(rp.X + mem.dx, rp.Y + mem.dy, rp.Z + mem.dz), clear = true }) end
		if #sides == 0 then
			flog("no floor spot found around the register, using the old guesses")
			for _, off in ipairs({ V3(-1.6, 0, 0), V3(1.6, 0, 0), V3(0, 0, -1.6), V3(0, 0, 1.6) }) do
				sides[#sides + 1] = { pos = rp + off + V3(0, 1, 0), clear = false }
			end
		end
		flog(("%d standing spots on the floor around the register (floor level %.1f)%s"):format(#sides, floorY, mem and ", remembered one first" or ""))
	end

	enterShop(rp)
	pcall(function() hum:UnequipTools() end)
	fire(ID.UNEQUIP) -- the server must see empty hands too
	task.wait(0.4)
	buildSides()
	local h0 = model:GetAttribute("Health") or 48
	local landed = false
	local landedPos
	for i, sd in ipairs(sides) do
		if Farm.Cancel then break end
		say(("%s: trying side %d/%d (%s)"):format(entry.key, i, #sides, sd.clear and "clear" or "blocked"))
		local arrived = walkTo(sd.pos, nil, 1.2)
		face(rp)
		task.wait(0.3)
		do
			local _, _, h2 = parts()
			local to = rp - h2.Position
			local flat = V3(to.X, 0, to.Z)
			local dot = flat.Magnitude > 0.1 and h2.CFrame.LookVector:Dot(flat.Unit) or 0
			flog(("before punching: distance %.1f, facing the register %.2f (1 = straight at it), %s"):format(flat.Magnitude, dot, playerState()))
		end
		local echoes = 0
		local pr = remote(ID.PUNCH)
		local conn = pr and pr.OnClientEvent:Connect(function(p) if p == lp then echoes = echoes + 1 end end)
		for _ = 1, 5 do
			punch()
			task.wait(0.62)
			if (model:GetAttribute("Health") or h0) < h0 or model:GetAttribute("TimedOut") == true then landed = true; landedPos = sd.pos; break end
		end
		if conn then conn:Disconnect() end
		flog(("side %d (arrived=%s): health %s -> %s, server answered %d punches"):format(i, tostring(arrived), tostring(h0), tostring(model:GetAttribute("Health")), echoes))
		if landed then break end
	end
	if landed and landedPos then
		standMem[entry.key] = { dx = landedPos.X - rp.X, dy = landedPos.Y - rp.Y, dz = landedPos.Z - rp.Z }
		pcall(function()
			if writefile then
				pcall(function() if makefolder then makefolder("ScrdsxScript") end end)
				writefile(STAND_FILE, game:GetService("HttpService"):JSONEncode(standMem))
			end
		end)
	end
	if not landed then
		say(entry.key .. ": punches do not hurt it (closed?), skipping it for 10 min"); cooldown(entry.key, 600); backToCar(); return false
	end
	say(entry.key .. ": breaking the register")
	local t0 = os.clock()
	while not Farm.Cancel and os.clock() - t0 < 20 and model:GetAttribute("TimedOut") ~= true do
		punch()
		task.wait(0.62)
	end
	task.wait(0.6)
	-- money drops are MeshParts named after you in Workspace.Drops
	local got, idle = 0, os.clock()
	local tried = {}
	while not Farm.Cancel and os.clock() - idle < 4 do
		local drops = workspace:FindFirstChild("Drops")
		local list = {}
		for _, d in ipairs(drops and drops:GetChildren() or {}) do
			if d.Name == lp.Name and d:IsA("BasePart") and (tried[d] or 0) < 3 then list[#list + 1] = d end
		end
		if #list == 0 then task.wait(0.3) else
			idle = os.clock()
			local items = {}
			for _, dd in ipairs(list) do items[#items + 1] = { part = dd, id = ACT.drop } end
			local first = items[1]
			walkTo(first.part.Position + V3(0, 1.5, 0), Farm.WalkSpeed, 2.5)
			local batch = batchAround(items, first)
			say(("%s: picking up money (%d at once)"):format(entry.key, #batch))
			holdBatch(batch)
			task.wait(0.15)
			for _, it in ipairs(batch) do
				if it.part.Parent then tried[it.part] = (tried[it.part] or 0) + 1 else got = got + 1 end
			end
			if #batch > 1 and got == 0 and Farm.Parallel then Farm.Parallel = false; flog("picking up several at once did not work, one at a time from now on") end
		end
	end
	Farm.done.registers = Farm.done.registers + 1
	cooldown(entry.key, 560)
	backToCar()
	return true
end

local function doRegisters()
	local list = {}
	local _, _, hrp = parts()
	local here = hrp and hrp.Position or V3()
	for _, e in ipairs(REGISTERS) do
		local lp0 = locationFor(e)
		if ready(e.key) and lp0 and (not Farm.Manual or (lp0 - here).Magnitude <= Farm.ManualRange) then list[#list + 1] = e end
	end
	if #list == 0 then
		if Farm.Manual then say("no cash register near you: drive to a shop (Tool Shop, Ares, Gas-N-Go, Osso, Farm Shop, Clothing Store)") end
		return false
	end
	table.sort(list, function(a, b) return (locationFor(a) - here).Magnitude < (locationFor(b) - here).Magnitude end)
	-- a register that turns out to be on cooldown only costs a short flight: go on to the next one
	for _, e in ipairs(list) do
		if Farm.Cancel then return true end
		local ok, res = pcall(robRegister, e)
		if not ok then
			print("[farm] " .. e.key .. " error: " .. tostring(res))
			flog("ERROR in " .. e.key .. ": " .. tostring(res))
			restoreChar()
			Farm.done.fails = Farm.done.fails + 1
			cooldown(e.key, 90)
			stats(); changed()
			return true
		end
		if res ~= "skip" then
			if res == false then Farm.done.fails = Farm.done.fails + 1 end
			stats(); changed()
			return true
		end
	end
	say("every register is on cooldown")
	return true
end

local function doBank()
	if not ready("bank") then return false end
	return tryRoutine("bank", function()
		local vault = workspace:FindFirstChild("Robberies") and workspace.Robberies:FindFirstChild("BankRobbery") and workspace.Robberies.BankRobbery:FindFirstChild("VaultDoor")
		if vault and vault:GetAttribute("Opened") == true then say("bank is already open / robbed"); cooldown("bank", 200); return true end
		if not bombCheck() and not buyBombs(1) then say("could not buy a bomb"); cooldown("bank", 90); return false end
		if not goNear(BANK.pos, "bank") then cooldown("bank", 90); return false end
		say("bank: walking in")
		local inside = walkTo(BANK.stand + V3(0, 1, 0), Farm.WalkSpeed, 3)
		if not inside then
			local _, _, h0 = parts()
			if not h0 or (h0.Position - BANK.stand).Magnitude > 14 then
				enterShop(BANK.stand) -- fallback: try the doors one by one
				inside = walkTo(BANK.stand + V3(0, 1, 0), Farm.WalkSpeed, 3)
			end
		end
		local _, _, hrpB = parts()
		if not inside and (not hrpB or (hrpB.Position - BANK.stand).Magnitude > 14) then
			say("bank: could not get to the vault door"); cooldown("bank", 90); backToCar(); return false
		end
		local bank = workspace:FindFirstChild("Robberies") and workspace.Robberies:FindFirstChild("BankRobbery")
		vault = bank and bank:FindFirstChild("VaultDoor")
		if vault then waitAttr(vault, "Enabled", true, 6) end
		face(BANK.target)
		say("bank: throwing the bomb")
		if not throwBomb(BANK.target) then say("bank: could not throw"); cooldown("bank", 90); backToCar(); return false end
		-- a thrown bomb does nothing until YOU detonate it (the game's "Detonate Bombs" button); in your recordings that was 1.6 to 2.5 s later
		local opened = false
		for i = 1, 4 do
			task.wait(i == 1 and 1.9 or 1.2)
			say("bank: detonating (try " .. i .. ")")
			fire(ID.DETONATE)
			if vault and waitAttr(vault, "Opened", true, 4) then opened = true; break end
		end
		if not opened then say("bank: vault did not open"); cooldown("bank", 120); backToCar(); return false end
		loot(bank, "bank")
		Farm.done.bank = Farm.done.bank + 1
		cooldown("bank", 580)
		backToCar()
		sellGold()
		return true
	end)
end

-- safes (jeweler / club): bomb each closed safe, then collect what comes out. EXPERIMENTAL: the throw target is the safe itself.
local function doSafeStore(key, label, pos, getFolder, getSafes, statKey)
	if not ready(key) then return false end
	return tryRoutine(key, function()
		if not bombCheck() and not buyBombs(key == "jeweler" and 2 or 1) then say("could not buy a bomb"); cooldown(key, 90); return false end
		if not goNear(pos, label) then cooldown(key, 90); return false end
		local folder, safes
		for _ = 1, 12 do
			folder = getFolder()
			safes = folder and getSafes(folder) or {}
			if #safes > 0 then break end
			task.wait(0.5)
		end
		if not folder or #safes == 0 then say(label .. ": safe not found"); cooldown(key, 120); backToCar(); return false end
		for _, s in ipairs(safes) do
			if Farm.Cancel then break end
			if s:GetAttribute("Opened") ~= true then
				local sp = where(s)
				local _, _, hrp = parts()
				local away = hrp.Position - sp
				away = V3(away.X, 0, away.Z)
				local stand = sp + (away.Magnitude > 0.1 and away.Unit * 6 or V3(6, 0, 0))
				say(label .. ": at the safe")
				walkTo(stand, Farm.WalkSpeed, 2)
				face(sp)
				if not throwBomb(sp) then say(label .. ": no bomb left"); break end
				for i = 1, 3 do -- the bomb only goes off when you detonate it
					task.wait(i == 1 and 1.9 or 1.2)
					fire(ID.DETONATE)
					if waitAttr(s, "Opened", true, 4) then break end
				end
			end
		end
		loot(folder, label)
		Farm.done[statKey] = Farm.done[statKey] + 1
		cooldown(key, 580)
		backToCar()
		return true
	end)
end

local function doJeweler()
	return doSafeStore("jeweler", "jeweler", JEWELER_POS,
		function() return workspace:FindFirstChild("Robberies") and workspace.Robberies:FindFirstChild("JewelleryStore") end,
		function(f)
			local list = {}
			local sf = f:FindFirstChild("Safes")
			for _, m in ipairs(sf and sf:GetChildren() or {}) do if m:IsA("Model") then list[#list + 1] = m end end
			return list
		end, "jeweler")
end
local function doClub()
	return doSafeStore("club", "club", CLUB_POS,
		function() return workspace:FindFirstChild("Robberies") and workspace.Robberies:FindFirstChild("Club Robbery") end,
		function(f)
			local m = f:FindFirstChild("Club")
			return m and { m } or {}
		end, "club")
end

-- what the HUD mini-map shows: shops (green = ready, grey = on cooldown), the bank, jeweler, club and the dealers that are loaded
local poiCache, poiAt = {}, 0
function Farm.POIs()
	if os.clock() - poiAt < 1 then return poiCache end
	poiAt = os.clock()
	local list = {}
	for _, e in ipairs(REGISTERS) do
		local p = locationFor(e)
		if p then list[#list + 1] = { pos = p, tag = "$", color = Color3.fromRGB(60, 190, 100), dim = not ready(e.key) } end
	end
	list[#list + 1] = { pos = BANK.pos, tag = "B", color = Color3.fromRGB(235, 185, 60), dim = not ready("bank") }
	list[#list + 1] = { pos = JEWELER_POS, tag = "J", color = Color3.fromRGB(70, 190, 230), dim = not ready("jeweler") }
	list[#list + 1] = { pos = CLUB_POS, tag = "C", color = Color3.fromRGB(220, 100, 190), dim = not ready("club") }
	local root = workspace:FindFirstChild("Spawned") and workspace.Spawned:FindFirstChild("Dealer")
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if d:IsA("BasePart") and d:GetAttribute("ItemStore") == "Dealer" and #list < 24 then
			list[#list + 1] = { pos = d.Position, tag = "D", color = Color3.fromRGB(150, 90, 220), dim = false }
		end
	end
	poiCache = list
	return list
end
function Farm.Earned()
	local m = Farm.moneyNow and Farm.moneyNow()
	if m and startMoney then return m - startMoney end
end

-- control ------------------------------------------------------------------------------------------------------------
local function runOnce(kind)
	if kind == "registers" then return doRegisters()
	elseif kind == "buybomb" then return tryRoutine("buybomb", function() return buyBombs(1) end)
	elseif kind == "bank" then Farm.cool.bank = nil; return doBank()
	elseif kind == "jeweler" then Farm.cool.jeweler = nil; return doJeweler()
	elseif kind == "club" then Farm.cool.club = nil; return doClub() end
end

local function wrongTeam()
	local t = lp.Team
	if t and t.Name ~= "Citizen" then
		say("switch to the Citizen team first (only citizens can rob and collect)")
		return true
	end
	return false
end

function Farm.Once(kind)
	if Farm.Busy or wrongTeam() then return end
	Farm.Busy, Farm.Cancel = true, false
	task.spawn(function()
		pcall(runOnce, kind)
		Farm.Busy = false
		if not Farm.Enabled then say("idle") end
	end)
end

function Farm.SetEnabled(v)
	if v == Farm.Enabled then return end
	if v and wrongTeam() then if Farm.Stopped then task.defer(Farm.Stopped) end return end
	Farm.Enabled = v
	if not v then
		Farm.Cancel = true
		if Farm.Tele then Farm.Tele.Stop() end
		say("stopping...")
		return
	end
	if Farm.Busy then return end
	Farm.Busy, Farm.Cancel = true, false
	task.spawn(function()
		while Farm.Enabled and not Farm.Cancel do
			local did = false
			if Farm.Registers and not Farm.Cancel then did = doRegisters() or did end
			if Farm.Bank and not Farm.Cancel then did = doBank() or did end
			if Farm.Jeweler and not Farm.Cancel then did = doJeweler() or did end
			if Farm.Club and not Farm.Cancel then did = doClub() or did end
			if not did then
				say("waiting for the stores to reset...")
				for _ = 1, 20 do if not Farm.Enabled then break end task.wait(0.5) end
			end
		end
		Farm.Busy = false
		say("off")
	end)
end

function Farm.Stop()
	Farm.Enabled = false
	Farm.Cancel = true
	if Farm.Tele then Farm.Tele.Stop() end
end

function Farm.Destroy()
	Farm.Stop()
	Farm.Changed = nil
end

stats()
return Farm
