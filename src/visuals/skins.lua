-- Skins (client-side, only YOU see them): paint your own character and / or the other players, or copy the look of any Roblox user onto your character.
-- Everything is tracked per character: the first time a part is touched its real values are saved, and switching a skin off (or unloading) puts every single one back,
-- including the things that hide a paint job (SurfaceAppearance, shirts, pants, the face decal) which are set aside while a skin is on and returned afterwards.
-- Nothing is sent to the server.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local ESP = __import("visuals/esp")

local function style(color, color2)
	return {
		Enabled = false, Color = color, Color2 = color2, Mode = "Solid", Material = "Neon", Transparency = 0, Speed = 1,
		Accessories = true, HideClothes = true, HideFace = false, Outline = false, OutlineColor = Color3.fromRGB(255, 255, 255), SeeThrough = true,
	}
end

local Skins = {
	Paint = style(Color3.fromRGB(243, 156, 18), Color3.fromRGB(150, 60, 20)),
	Others = style(Color3.fromRGB(255, 255, 255), Color3.fromRGB(110, 110, 120)),
	KeepLook = true, Info = "ready",
}
Skins.Others.TeamColors = true
Skins.Modes = { "Solid", "Two-tone", "Gradient", "Flow", "Rainbow", "Pulse" }

local MATS = { "Plastic", "SmoothPlastic", "Neon", "ForceField", "Glass", "Metal", "Foil", "Ice", "Marble", "Granite", "DiamondPlate", "Wood", "WoodPlanks", "Brick", "Concrete", "Slate", "Fabric", "CorrodedMetal", "Sand", "Cobblestone" }
Skins.Materials = {}
for _, m in ipairs(MATS) do
	if Enum.Material[m] then Skins.Materials[#Skins.Materials + 1] = m end
end

local function C(r, g, b) return Color3.fromRGB(r, g, b) end
-- name, colour, second colour, mode, material, see-through, outline colour (nil = no outline)
local PRE = {
	{ "Gold", C(255, 196, 40), C(190, 120, 10), "Gradient", "Metal", 0 },
	{ "Chrome", C(225, 230, 240), C(120, 130, 150), "Gradient", "Metal", 0 },
	{ "Neon violet", C(150, 90, 255), C(60, 30, 140), "Gradient", "Neon", 0 },
	{ "Matrix", C(40, 255, 110), C(0, 90, 40), "Flow", "Neon", 0 },
	{ "Lava", C(255, 110, 30), C(190, 20, 10), "Flow", "Neon", 0 },
	{ "Fire", C(255, 200, 40), C(210, 30, 10), "Flow", "Neon", 0 },
	{ "Ocean", C(30, 170, 255), C(0, 210, 190), "Flow", "Neon", 0 },
	{ "Galaxy", C(150, 70, 255), C(30, 60, 200), "Flow", "Neon", 0 },
	{ "Sunset", C(255, 140, 60), C(255, 60, 140), "Gradient", "Neon", 0 },
	{ "Cyber", C(0, 230, 255), C(255, 30, 200), "Two-tone", "Neon", 0 },
	{ "Candy", C(255, 150, 200), C(255, 255, 255), "Two-tone", "SmoothPlastic", 0 },
	{ "Toxic", C(170, 255, 30), C(20, 60, 10), "Gradient", "Neon", 0, C(170, 255, 30) },
	{ "Ruby", C(210, 20, 60), C(120, 0, 30), "Gradient", "Glass", 0.1 },
	{ "Emerald", C(20, 200, 110), C(0, 100, 60), "Gradient", "Glass", 0.1 },
	{ "Sapphire", C(30, 90, 230), C(10, 30, 120), "Gradient", "Glass", 0.1 },
	{ "Diamond", C(225, 250, 255), C(150, 215, 255), "Gradient", "Glass", 0.3, C(220, 250, 255) },
	{ "Obsidian", C(14, 10, 22), C(50, 20, 80), "Gradient", "Glass", 0, C(120, 60, 220) },
	{ "Hologram", C(0, 220, 255), C(0, 120, 200), "Gradient", "ForceField", 0.25, C(0, 240, 255) },
	{ "Ice", C(170, 225, 255), C(90, 160, 230), "Gradient", "Ice", 0.15 },
	{ "Glass", C(210, 230, 255), C(170, 200, 240), "Solid", "Glass", 0.45 },
	{ "Ghost", C(255, 255, 255), C(200, 200, 215), "Solid", "ForceField", 0.2 },
	{ "Shadow", C(14, 14, 18), C(40, 40, 50), "Gradient", "SmoothPlastic", 0, C(90, 90, 110) },
	{ "Camo", C(78, 110, 58), C(46, 60, 34), "Two-tone", "Granite", 0 },
	{ "Wood", C(150, 100, 55), C(100, 65, 35), "Two-tone", "WoodPlanks", 0 },
	{ "Brick", C(170, 70, 55), C(120, 45, 35), "Two-tone", "Brick", 0 },
	{ "Rainbow", C(255, 80, 80), C(80, 80, 255), "Rainbow", "Neon", 0 },
	{ "Heartbeat", C(255, 40, 70), C(120, 0, 25), "Pulse", "Neon", 0 },
}
Skins.Presets = {}
for _, p in ipairs(PRE) do
	if Enum.Material[p[5]] then
		Skins.Presets[#Skins.Presets + 1] = { name = p[1], color = p[2], color2 = p[3], mode = p[4], material = p[5], transparency = p[6], outline = p[7] }
	end
end
Skins.PresetNames = {}
for _, p in ipairs(Skins.Presets) do Skins.PresetNames[#Skins.PresetNames + 1] = p.name end

-- RECORDS: one per painted character --------------------------------------------------------------------------------------------
local records = setmetatable({}, { __mode = "k" }) -- character -> record
local conn

local function category(part)
	local n = part.Name
	if n == "Head" then return "head" end
	if n:find("Torso", 1, true) then return "torso" end
	if n:find("Arm", 1, true) or n:find("Hand", 1, true) then return "arm" end
	if n:find("Leg", 1, true) or n:find("Foot", 1, true) then return "leg" end
	return "other"
end

local function newRecord(ch, kind)
	local rec = { ch = ch, kind = kind, parts = {}, saved = {}, stash = {}, dirty = true, sig = nil, lastForce = 0 }
	rec.conn = ch.DescendantAdded:Connect(function() rec.dirty = true end)
	records[ch] = rec
	return rec
end

local function collect(rec)
	rec.parts = {}
	local minY, maxY = math.huge, -math.huge
	for _, d in ipairs(rec.ch:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			local acc = d.Parent and d.Parent:IsA("Accessory") or false
			rec.parts[#rec.parts + 1] = { part = d, cat = category(d), acc = acc }
			local y = d.Position.Y
			if y < minY then minY = y end
			if y > maxY then maxY = y end
		end
	end
	rec.minY, rec.span = minY, math.max(maxY - minY, 0.1)
end

local function save(rec, part)
	if rec.saved[part] then return rec.saved[part] end
	local o = { Color = part.Color, Material = part.Material, Transparency = part.Transparency, Reflectance = part.Reflectance }
	if part:IsA("MeshPart") then o.Tex = part.TextureID end
	rec.saved[part] = o
	return o
end

-- set aside everything that would hide a paint job; remembered so it can be put back
local function setAside(rec, st)
	for _, d in ipairs(rec.ch:GetDescendants()) do
		if not rec.stash[d] then
			if d:IsA("SurfaceAppearance") then
				rec.stash[d] = { parent = d.Parent }
				d.Parent = nil
			elseif st.HideClothes and (d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic")) then
				rec.stash[d] = { parent = d.Parent }
				d.Parent = nil
			elseif st.HideFace and d:IsA("Decal") and d.Name == "face" then
				rec.stash[d] = { transparency = d.Transparency }
				d.Transparency = 1
			end
		end
	end
end

local function restoreExtras(rec)
	for inst, o in pairs(rec.stash) do
		pcall(function()
			if o.parent then
				if o.parent.Parent then inst.Parent = o.parent end
			else
				inst.Transparency = o.transparency
			end
		end)
	end
	rec.stash = {}
end

local function restore(rec)
	for part, o in pairs(rec.saved) do
		pcall(function()
			if part.Parent then
				part.Color, part.Material, part.Transparency, part.Reflectance = o.Color, o.Material, o.Transparency, o.Reflectance
				if o.Tex ~= nil then part.TextureID = o.Tex end
			end
		end)
	end
	restoreExtras(rec)
	if rec.glow then pcall(function() rec.glow:Destroy() end); rec.glow = nil end
	if rec.conn then rec.conn:Disconnect(); rec.conn = nil end
	if rec.ch then records[rec.ch] = nil end
end

-- COLOURS ----------------------------------------------------------------------------------------------------------------------------
local function colorFor(st, base, base2, cat, y01, t, idx)
	local m = st.Mode
	if m == "Solid" then return base end
	if m == "Two-tone" then return (cat == "head" or cat == "torso") and base or base2 end
	if m == "Gradient" then return base2:Lerp(base, y01) end
	if m == "Flow" then return base:Lerp(base2, (math.sin((y01 * 2 - t * st.Speed * 0.8) * math.pi) + 1) / 2) end
	if m == "Rainbow" then return Color3.fromHSV((y01 * 0.5 + t * 0.15 * st.Speed) % 1, 0.8, 1) end
	if m == "Pulse" then
		local k = 0.5 + 0.5 * math.sin(t * 3 * st.Speed)
		return base2:Lerp(base, k)
	end
	return base
end

local function animated(st) return st.Mode == "Flow" or st.Mode == "Rainbow" or st.Mode == "Pulse" end

local function sigOf(st, base, base2)
	return table.concat({ st.Mode, st.Material, tostring(st.Transparency), tostring(st.Accessories), tostring(st.HideClothes), tostring(st.HideFace), tostring(st.Outline),
		tostring(st.SeeThrough), tostring(base), tostring(base2), tostring(st.OutlineColor) }, "|")
end

local function apply(rec, st, base, base2, t)
	if rec.dirty then
		collect(rec)
		rec.dirty = false
		rec.sig = nil
	end
	local sig = sigOf(st, base, base2)
	local anim = animated(st)
	local force = os.clock() - rec.lastForce > 2 -- the game may reset colours: put the skin back every couple of seconds
	if sig == rec.sig and not anim and not force then return end
	if sig ~= rec.sig or force then setAside(rec, st) end
	rec.sig = sig
	if force then rec.lastForce = os.clock() end
	local mat = Enum.Material[st.Material] or Enum.Material.Neon
	local refl = (st.Material == "Metal" or st.Material == "Foil") and 0.25 or 0
	for i, p in ipairs(rec.parts) do
		local part = p.part
		if part.Parent then
			if p.acc and not st.Accessories then
				-- hats / accessories are left as they are when the switch says so
			else
				local o = save(rec, part)
				local y01 = rec.span > 0 and math.clamp((part.Position.Y - rec.minY) / rec.span, 0, 1) or 0.5
				part.Color = colorFor(st, base, base2, p.cat, y01, t, i)
				part.Material = mat
				part.Reflectance = refl
				-- parts that were invisible stay invisible (hidden accessory handles, the root); everything else gets the chosen see-through value
				part.Transparency = o.Transparency >= 0.99 and o.Transparency or st.Transparency
				if o.Tex ~= nil and part.TextureID ~= "" then part.TextureID = "" end
			end
		end
	end
	-- outline glow
	if st.Outline then
		if not (rec.glow and rec.glow.Parent) then
			local h = Instance.new("Highlight")
			h.Name = "ScrdsxGlow"; h.FillTransparency = 1; h.OutlineTransparency = 0; h.Adornee = rec.ch; h.Parent = rec.ch
			rec.glow = h
		end
		rec.glow.OutlineColor = st.OutlineColor
		rec.glow.DepthMode = st.SeeThrough and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
	elseif rec.glow then
		pcall(function() rec.glow:Destroy() end); rec.glow = nil
	end
end

-- one pass over everybody ---------------------------------------------------------------------------------------------------------------
local function tick()
	local P, O = Skins.Paint, Skins.Others
	local t = os.clock()

	-- me
	local mine = lp.Character
	for ch, rec in pairs(records) do
		if rec.kind == "me" and (not P.Enabled or ch ~= mine) then restore(rec) end
	end
	if P.Enabled and mine and mine.Parent then
		local rec = records[mine] or newRecord(mine, "me")
		apply(rec, P, P.Color, P.Color2, t)
	end

	-- the others
	local live = {}
	if O.Enabled then
		for _, plr in ipairs(Players:GetPlayers()) do
			local ch = plr.Character
			if plr ~= lp and ch and ch.Parent then
				live[ch] = true
				local base, base2 = O.Color, O.Color2
				if O.TeamColors then
					local _, c = ESP.RoleOf(plr)
					base = c
					base2 = c:Lerp(Color3.new(0, 0, 0), 0.55)
				end
				local rec = records[ch] or newRecord(ch, "other")
				apply(rec, O, base, base2, t)
			end
		end
	end
	for ch, rec in pairs(records) do
		if rec.kind == "other" and not live[ch] then restore(rec) end
	end
end

-- called whenever a switch or a setting changes: runs a pass right now (so switching off restores immediately)
function Skins.Refresh()
	for _, rec in pairs(records) do rec.dirty = true end
	pcall(tick)
end

function Skins.ApplyPreset(which, target)
	local p = which
	if type(which) == "string" then
		for _, x in ipairs(Skins.Presets) do if x.name == which then p = x end end
	end
	if type(p) ~= "table" then return nil end
	local S = target or Skins.Paint
	S.Color, S.Color2, S.Mode, S.Material, S.Transparency = p.color, p.color2 or p.color, p.mode or "Solid", p.material, p.transparency or 0
	if p.outline then S.Outline = true; S.OutlineColor = p.outline else S.Outline = false end
	if S == Skins.Others then S.TeamColors = false end
	Skins.Refresh()
	return p
end

-- COPY A ROBLOX AVATAR ------------------------------------------------------------------------------------------------------------------
local originalDesc, lastWho

function Skins.CopyUser(who)
	who = tostring(who or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if who == "" then return false, "type a username or user id" end
	local ch = lp.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum then return false, "no character" end
	local uid = tonumber(who)
	if not uid then
		local ok, id = pcall(function() return Players:GetUserIdFromNameAsync(who) end)
		if not ok or not id then return false, "no Roblox user with that name" end
		uid = id
	end
	local ok, desc = pcall(function() return Players:GetHumanoidDescriptionFromUserId(uid) end)
	if not ok or not desc then return false, "could not load that avatar" end
	if not originalDesc then pcall(function() originalDesc = hum:GetAppliedDescription() end) end
	local ok2, err = pcall(function() hum:ApplyDescription(desc) end)
	if not ok2 then return false, "the game refused it: " .. tostring(err) end
	lastWho = who
	return true
end

function Skins.RestoreLook()
	local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
	if hum and originalDesc then pcall(function() hum:ApplyDescription(originalDesc) end) end
	lastWho = nil
end

-- LIFE ---------------------------------------------------------------------------------------------------------------------------------------
local charConn

function Skins.Start()
	if conn then return end
	local acc = 0
	conn = RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < 0.066 then return end
		acc = 0
		local ok, err = pcall(tick)
		if not ok and Skins.Info ~= "error" then Skins.Info = "error"; warn("[skins] " .. tostring(err)) end
	end)
	-- keep a copied look after respawning
	charConn = lp.CharacterAdded:Connect(function()
		if Skins.KeepLook and lastWho then
			task.wait(1.2)
			Skins.CopyUser(lastWho)
		end
	end)
end

function Skins.Destroy()
	if conn then conn:Disconnect(); conn = nil end
	if charConn then charConn:Disconnect(); charConn = nil end
	Skins.Paint.Enabled, Skins.Others.Enabled = false, false
	for _, rec in pairs(records) do pcall(restore, rec) end
	Skins.RestoreLook()
end

return Skins
