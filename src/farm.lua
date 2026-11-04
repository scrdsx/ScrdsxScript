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
	{ key = "Ares", folder = "Ares Fuel Station Robbery", pos = V3(-839, 7, 1530) },
	{ key = "Gas-N-Go", folder = "Gas-N-Go Fuel Station Robbery", pos = V3(-1541, 9, 3771) },
	{ key = "Osso", folder = "Osso Fuel Station Robbery", pos = nil },
	{ key = "Farm Shop", folder = "Farm Shop Robbery", pos = nil },
	{ key = "Clothing Store", folder = "Clothing Store Robbery", pos = nil },
}

local Farm = {
	Enabled = false, Busy = false, Cancel = false,
	Registers = true, Bank = true, Jeweler = false, Club = false,
	SellGold = true, SellCalls = 1, WalkSpeed = 60,
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
local function flog(s)
	logbuf[#logbuf + 1] = ("[+%6.1f] %s  @%s"):format(os.clock() - T0, s, posStr())
	if #logbuf > 400 then table.remove(logbuf, 1) end
end
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
local function walkTo(pos, speed, stop)
	local c, hum, hrp = parts()
	if not hrp then return false end
	speed, stop = speed or Farm.WalkSpeed, stop or 2.5
	local saved = {}
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide then saved[#saved + 1] = d; d.CanCollide = false end
	end
	local ok = false
	local run, err = pcall(function()
		local t0 = os.clock()
		local limit = (hrp.Position - pos).Magnitude / speed * 2 + 4
		while os.clock() - t0 < limit and not Farm.Cancel and hrp.Parent do
			local dt = RunService.Heartbeat:Wait()
			local to = pos - hrp.Position
			local d = to.Magnitude
			if d <= stop then ok = true; break end
			local step = math.min(d, speed * math.min(dt, 0.1))
			hrp.CFrame = hrp.CFrame + to.Unit * step
			hrp.AssemblyLinearVelocity = V3()
			hrp.AssemblyAngularVelocity = V3()
		end
	end)
	for _, p in ipairs(saved) do if p.Parent then p.CanCollide = true end end
	restoreChar()
	if not run then flog("walkTo error: " .. tostring(err)) end
	return ok
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
	local _, hum, hrp = parts()
	flog(("teleport result=%s info=%s"):format(tostring(Tele.LastResult), tostring(Tele.Info)))
	if Tele.LastResult ~= "ok" then say("could not drive to " .. name .. ": " .. tostring(Tele.Info)); return false end
	if not hrp or (hrp.Position - pos).Magnitude > 250 then say("arrived too far from " .. name); return false end
	if hum and hum.SeatPart then
		hum.Sit = false
		task.wait(0.35)
		if hum.SeatPart then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end); task.wait(0.4) end
	end
	return true
end
local function backToCar()
	local _, seat = myCar()
	if not seat then return false end
	say("back to the car")
	walkTo(seat.Position + V3(0, 3, 0), Farm.WalkSpeed, 4)
	Farm.Tele.GoToCar()
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

-- pick up everything under `root` that is switched on (money = id 2vd, items/gold = id 7Rm)
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
		say(("%s: collecting %d left"):format(label, #list))
		walkTo(it.part.Position + V3(0, 1.5, 0), Farm.WalkSpeed, 2.5)
		holdInteract(it.part, it.id)
		task.wait(0.15)
		tried[it.part] = (tried[it.part] or 0) + 1
		if not it.part.Parent or it.part:GetAttribute("Enabled") ~= true then got = got + 1 end
	end
	return got
end

local function hasBomb()
	local c = lp.Character
	local bp = lp:FindFirstChild("Backpack")
	return (bp and bp:FindFirstChild("Bomb") ~= nil) or (c and c:FindFirstChild("Bomb") ~= nil)
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
			task.wait(0.9)
		end
		return hasBomb()
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
	fire(ID.EQUIP, "Bomb")
	local t = os.clock()
	local tool
	while os.clock() - t < 2.5 do
		tool = c:FindFirstChild("Bomb")
		if tool then break end
		task.wait(0.1)
	end
	if not tool then
		fire(ID.EQUIP, "Bomb") -- it may have toggled off
		task.wait(0.8)
		tool = c:FindFirstChild("Bomb")
	end
	if not tool then return false end
	task.wait(0.8)
	fire(ID.THROW, tool, target.X, target.Y, target.Z)
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
	local Tele = Farm.Tele
	for _, l in ipairs(Tele and Tele.Locations or {}) do
		if l.name:lower():find(entry.key:lower(), 1, true) then return l.pos end
	end
	return entry.pos
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
	if model:GetAttribute("TimedOut") == true then say(entry.key .. " was already robbed"); cooldown(entry.key, 150); backToCar(); return true end
	local body = model:FindFirstChild("Body") or model:FindFirstChildWhichIsA("BasePart")
	local rp = body and body.Position or where(model)
	local _, hum, hrp = parts()
	local away = hrp.Position - rp
	away = V3(away.X, 0, away.Z)
	local stand = rp + (away.Magnitude > 0.1 and away.Unit * 3 or V3(3, 0, 0)) + V3(0, 1, 0)
	say(entry.key .. ": walking to the register")
	walkTo(stand, Farm.WalkSpeed, 1.5)
	face(rp)
	pcall(function() hum:UnequipTools() end)
	task.wait(0.3)
	local h0 = model:GetAttribute("Health")
	local t0, swings = os.clock(), 0
	say(entry.key .. ": breaking the register")
	while not Farm.Cancel and os.clock() - t0 < 25 do
		if model:GetAttribute("TimedOut") == true then break end
		fire(ID.PUNCH)
		swings = swings + 1
		task.wait(0.62)
		if swings == 5 and model:GetAttribute("Health") == h0 then
			say(entry.key .. ": punches do not hit (too far?)"); cooldown(entry.key, 120); backToCar(); return false
		end
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
			local d = list[1]
			say(entry.key .. ": picking up money")
			walkTo(d.Position + V3(0, 1.5, 0), Farm.WalkSpeed, 2.5)
			holdInteract(d, ACT.drop)
			tried[d] = (tried[d] or 0) + 1
			got = got + 1
		end
	end
	Farm.done.registers = Farm.done.registers + 1
	cooldown(entry.key, 560)
	backToCar()
	return true
end

local function doRegisters()
	local list = {}
	for _, e in ipairs(REGISTERS) do if ready(e.key) then list[#list + 1] = e end end
	if #list == 0 then return false end
	local _, _, hrp = parts()
	local here = hrp and hrp.Position or V3()
	table.sort(list, function(a, b)
		local pa, pb = locationFor(a) or V3(1e5, 0, 1e5), locationFor(b) or V3(1e5, 0, 1e5)
		return (pa - here).Magnitude < (pb - here).Magnitude
	end)
	return tryRoutine(list[1].key, function() return robRegister(list[1]) end)
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
