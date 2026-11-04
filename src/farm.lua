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
	EQUIP = "910a8b37-75ee-42aa-897a-ad920fa54120",    -- ("Bomb")  toggles the tool
	THROW = "78362192-b9dc-4744-9e59-0d72a5b791cf",    -- (tool, x, y, z)
	THROWDONE = "d1152c57-eaab-4cb4-8861-404a5640d434", -- ()
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
	SellGold = true, SellCalls = 1, WalkSpeed = 60, InstantMove = false, Parallel = true, bombs = 0,
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
local function stats()
	local d = Farm.done
	Farm.Stats = ("reg %d  bank %d  jewel %d  club %d  fails %d"):format(d.registers, d.bank, d.jeweler, d.club, d.fails)
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
	local t, lastPos, lastT = os.clock(), hrp.Position, os.clock()
	while os.clock() - t < timeout and not Farm.Cancel and hrp.Parent do
		task.wait(0.1)
		if near(hrp.Position, target, r) then return true end
		if os.clock() - lastT > 1.2 then
			if (hrp.Position - lastPos).Magnitude < 1.5 then hum.Jump = true end -- stuck on something: hop
			lastPos, lastT = hrp.Position, os.clock()
			hum:MoveTo(target)
		end
	end
	return near(hrp.Position, target, r)
end
local function walkTo(pos, _, stop)
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
		flog("no path found, walking straight")
		waypoints = { { Position = pos, Action = Enum.PathWaypointAction.Walk } }
	end
	for _, wp in ipairs(waypoints) do
		if Farm.Cancel then return false end
		if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
		moveStep(hum, hrp, wp.Position, 4, 3)
	end
	if not near(hrp.Position, pos, stop) then moveStep(hum, hrp, pos, 5, stop) end
	return near(hrp.Position, pos, stop + 1.5)
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

-- drive (Teleports module) to a place and step out of the car
local function goNear(pos, name)
	local Tele = Farm.Tele
	say("driving to " .. name)
	stream(pos)
	Tele.GoTo({ name = name, pos = pos })
	task.wait(0.2)
	while Tele.Busy and not Farm.Cancel do task.wait(0.2) end
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
	local _, _, hrp = parts()
	if hrp and (hrp.Position - seat.Position).Magnitude > 200 then walkTo(seat.Position + V3(0, 3, 0), Farm.WalkSpeed, 4) end
	Farm.Tele.GoToCar() -- sits you in the seat directly (that move is accepted)
	task.wait(0.3)
	while Farm.Tele.Busy and not Farm.Cancel do task.wait(0.2) end
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
	while os.clock() - t < (hold or 2.6) do
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
	if Farm.Parallel then
		for _, o in ipairs(list) do
			if o ~= first and #batch < 4 and (o.part.Position - first.part.Position).Magnitude < 8 then batch[#batch + 1] = o end
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
		table.sort(list, function(a, b) return (a.part.Position - here).Magnitude < (b.part.Position - here).Magnitude end)
		local it = list[1]
		local batch = batchAround(list, it)
		say(("%s: collecting %d left (%d at once)"):format(label, #list, #batch))
		walkTo(it.part.Position + V3(0, 1.5, 0), Farm.WalkSpeed, 2.5)
		holdBatch(batch)
		task.wait(0.15)
		got = got + afterBatch(batch, tried)
	end
	return got
end

-- bombs are NOT tools in your backpack until you equip them (the recording shows no backpack change after buying),
-- so the script keeps its own count: +1 per buy message, -1 per throw
local function hasBomb()
	return Farm.bombs > 0
end

-- nearest dealer that is loaded (they move around the map)
local function findDealer()
	local _, _, hrp = parts()
	local here = hrp and hrp.Position or V3()
	local best, bd
	local root = workspace:FindFirstChild("Spawned") and workspace.Spawned:FindFirstChild("Dealer")
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if d:IsA("BasePart") and d:GetAttribute("ItemStore") == "Dealer" then
			local dist = (d.Position - here).Magnitude
			if not bd or dist < bd then best, bd = d, dist end
		end
	end
	return best
end

-- go to the nearest dealer and run `fn(dealerPart)` while standing next to it
local function atDealer(fn)
	local d = findDealer()
	if not d then say("no dealer is loaded nearby"); return false end
	if not goNear(d.Position, "dealer") then return false end
	if not walkTo(d.Position + V3(0, 1, 0), Farm.WalkSpeed, 3) then return false end
	fire(ID.INTERACT, d, ACT.dealer, "stop") -- opens the shop
	task.wait(0.4)
	local ok = fn(d)
	fire(ID.INTERACT, d, ACT.dealer, "cancel")
	return ok
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
		Farm.bombs = 0 -- the game did not give us a bomb: the count was wrong
		flog("equipping the bomb failed: no bomb in the inventory")
		return false
	end
	task.wait(0.8)
	fire(ID.THROW, tool, target.X, target.Y, target.Z)
	Farm.bombs = math.max(0, Farm.bombs - 1)
	task.wait(0.9)
	fire(ID.THROWDONE)
	task.wait(0.5)
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
local function enterShop(rp)
	local _, _, hrp = parts()
	local flat = V3(hrp.Position.X - rp.X, 0, hrp.Position.Z - rp.Z)
	if flat.Magnitude < 12 then return end -- already inside
	local doors = doorsNear(rp, 60)
	for i = 1, math.min(#doors, 3) do
		flog(("door candidate %d: %s (%s) at (%.0f,%.0f,%.0f), %.0f studs from the register"):format(i, doors[i].inst.Name, doors[i].tag, doors[i].pos.X, doors[i].pos.Y, doors[i].pos.Z, doors[i].dist))
	end
	local d = doors[1]
	if not d then flog("no door found near the register"); return end
	local out = V3(hrp.Position.X - d.pos.X, 0, hrp.Position.Z - d.pos.Z)
	out = out.Magnitude > 0.1 and out.Unit or V3(1, 0, 0)
	say("going in through the door")
	walkTo(d.pos + out * 6 + V3(0, 1, 0), nil, 2.5)  -- in front of the door (it opens when you are close)
	task.wait(0.8)
	walkTo(d.pos - out * 5 + V3(0, 1, 0), nil, 2.5)   -- through it
end

local function robRegister(entry)
	local pos = locationFor(entry)
	if not pos then cooldown(entry.key, 300); return false end
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

	-- standing spots around the register; the ones with a clear line to it come first (the counter may block one side)
	local rparams = RaycastParams.new()
	rparams.FilterType = Enum.RaycastFilterType.Exclude
	rparams.FilterDescendantsInstances = { lp.Character, (myCar()) }
	local sides = {}
	for _, off in ipairs({ V3(-1.6, 0, 0), V3(1.6, 0, 0), V3(0, 0, -1.6), V3(0, 0, 1.6) }) do
		local sp = rp + off
		local origin = V3(sp.X, rp.Y, sp.Z)
		local hit = workspace:Raycast(origin, rp - origin, rparams)
		sides[#sides + 1] = { pos = sp + V3(0, 1, 0), clear = hit == nil or hit.Instance:IsDescendantOf(model), d = (sp - hrp.Position).Magnitude }
	end
	table.sort(sides, function(a, b)
		if a.clear ~= b.clear then return a.clear end
		return a.d < b.d
	end)

	enterShop(rp)
	pcall(function() hum:UnequipTools() end)
	local h0 = model:GetAttribute("Health") or 48
	local landed = false
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
			if (model:GetAttribute("Health") or h0) < h0 or model:GetAttribute("TimedOut") == true then landed = true; break end
		end
		if conn then conn:Disconnect() end
		flog(("side %d (arrived=%s): health %s -> %s, server answered %d punches"):format(i, tostring(arrived), tostring(h0), tostring(model:GetAttribute("Health")), echoes))
		if landed then break end
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
			local batch = batchAround(items, first)
			say(("%s: picking up money (%d at once)"):format(entry.key, #batch))
			walkTo(first.part.Position + V3(0, 1.5, 0), Farm.WalkSpeed, 2.5)
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
	for _, e in ipairs(REGISTERS) do if ready(e.key) and locationFor(e) then list[#list + 1] = e end end
	if #list == 0 then return false end
	local _, _, hrp = parts()
	local here = hrp and hrp.Position or V3()
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
		if not hasBomb() and not buyBombs(1) then say("could not buy a bomb"); cooldown("bank", 90); return false end
		if not goNear(BANK.pos, "bank") then cooldown("bank", 90); return false end
		say("bank: walking in")
		walkTo(BANK.stand + V3(0, 1, 0), Farm.WalkSpeed, 2)
		local bank = workspace:FindFirstChild("Robberies") and workspace.Robberies:FindFirstChild("BankRobbery")
		vault = bank and bank:FindFirstChild("VaultDoor")
		if vault then waitAttr(vault, "Enabled", true, 6) end
		face(BANK.target)
		say("bank: throwing the bomb")
		if not throwBomb(BANK.target) then say("bank: could not throw"); cooldown("bank", 90); backToCar(); return false end
		say("bank: waiting for the vault")
		if not (vault and waitAttr(vault, "Opened", true, 15)) then say("bank: vault did not open"); cooldown("bank", 120); backToCar(); return false end
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
		if not hasBomb() and not buyBombs(key == "jeweler" and 2 or 1) then say("could not buy a bomb"); cooldown(key, 90); return false end
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
				if not hasBomb() then say(label .. ": no bomb left"); break end
				throwBomb(sp)
				waitAttr(s, "Opened", true, 12)
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

-- control ------------------------------------------------------------------------------------------------------------
local function runOnce(kind)
	if kind == "registers" then return doRegisters()
	elseif kind == "bank" then Farm.cool.bank = nil; return doBank()
	elseif kind == "jeweler" then Farm.cool.jeweler = nil; return doJeweler()
	elseif kind == "club" then Farm.cool.club = nil; return doClub() end
end

function Farm.Once(kind)
	if Farm.Busy then return end
	Farm.Busy, Farm.Cancel = true, false
	task.spawn(function()
		pcall(runOnce, kind)
		Farm.Busy = false
		if not Farm.Enabled then say("idle") end
	end)
end

function Farm.SetEnabled(v)
	if v == Farm.Enabled then return end
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
