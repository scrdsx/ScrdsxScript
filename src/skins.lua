-- Skins (client-side, only YOU see them): paint your own character (colour + material + transparency, presets), paint the other players, or copy
-- the look of any Roblox user onto your character. Nothing is sent to the server; it comes back to normal when you turn it off or rejoin.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local ESP = __import("esp")

local Skins = {
	Paint = { Enabled = false, Color = Color3.fromRGB(139, 92, 246), Material = "Neon", Transparency = 0, Rainbow = false, Accessories = true },
	Others = { Enabled = false, Color = Color3.fromRGB(255, 255, 255), Material = "ForceField", Transparency = 0, TeamColors = true, Rainbow = false },
	KeepLook = true, Info = "ready",
}
Skins.Materials = { "Plastic", "SmoothPlastic", "Neon", "ForceField", "Glass", "Metal", "Foil", "Ice", "Marble", "Granite", "DiamondPlate" }
Skins.Presets = {
	{ name = "Gold", color = Color3.fromRGB(255, 196, 40), material = "Metal", transparency = 0 },
	{ name = "Chrome", color = Color3.fromRGB(225, 230, 240), material = "Metal", transparency = 0 },
	{ name = "Neon violet", color = Color3.fromRGB(150, 90, 255), material = "Neon", transparency = 0 },
	{ name = "Matrix", color = Color3.fromRGB(40, 255, 110), material = "Neon", transparency = 0 },
	{ name = "Lava", color = Color3.fromRGB(255, 110, 30), material = "Neon", transparency = 0 },
	{ name = "Ice", color = Color3.fromRGB(170, 225, 255), material = "Ice", transparency = 0.15 },
	{ name = "Glass", color = Color3.fromRGB(210, 230, 255), material = "Glass", transparency = 0.45 },
	{ name = "Shadow", color = Color3.fromRGB(14, 14, 18), material = "SmoothPlastic", transparency = 0 },
	{ name = "Ghost", color = Color3.fromRGB(255, 255, 255), material = "ForceField", transparency = 0.2 },
}

local originals = setmetatable({}, { __mode = "k" }) -- part -> { Color, Material, Transparency, Texture }
local appliedOther = setmetatable({}, { __mode = "k" })
local conn
local originalDesc, lastWho

local function remember(part)
	if not originals[part] then
		originals[part] = { Color = part.Color, Material = part.Material, Transparency = part.Transparency, Reflectance = part.Reflectance }
		if part:IsA("MeshPart") then originals[part].Tex = part.TextureID end
	end
	return originals[part]
end

local function restoreCharacter(ch)
	if not ch then return end
	for _, d in ipairs(ch:GetDescendants()) do
		local o = originals[d]
		if o then
			pcall(function()
				d.Color, d.Material, d.Transparency, d.Reflectance = o.Color, o.Material, o.Transparency, o.Reflectance
				if o.Tex ~= nil then d.TextureID = o.Tex end
			end)
			originals[d] = nil
		end
	end
end

local function paintCharacter(ch, color, material, transparency, accessories)
	local mat = Enum.Material[material] or Enum.Material.Neon
	for _, d in ipairs(ch:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			local isAcc = d.Parent and d.Parent:IsA("Accessory")
			if accessories or not isAcc then
				remember(d)
				d.Color = color
				d.Material = mat
				d.Reflectance = (material == "Metal" or material == "Foil") and 0.25 or 0
				if d.Name == "Head" or not isAcc then d.Transparency = transparency elseif d.Transparency < 1 then d.Transparency = transparency end
				if d:IsA("MeshPart") and d.TextureID ~= "" then d.TextureID = "" end
			elseif isAcc then
				-- accessories hidden by the "Accessories" switch: leave them alone
			end
		end
	end
end

local function step()
	local P, O = Skins.Paint, Skins.Others
	local t = os.clock()
	if P.Enabled then
		local col = P.Rainbow and Color3.fromHSV((t * 0.2) % 1, 0.8, 1) or P.Color
		if lp.Character then paintCharacter(lp.Character, col, P.Material, P.Transparency, P.Accessories) end
	end
	if O.Enabled then
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp and plr.Character then
				local col = O.Color
				if O.Rainbow then col = Color3.fromHSV(((t * 0.2) + plr.UserId % 10 / 10) % 1, 0.8, 1)
				elseif O.TeamColors then local _, c = ESP.RoleOf(plr); col = c end
				paintCharacter(plr.Character, col, O.Material, O.Transparency, true)
				appliedOther[plr.Character] = true
			end
		end
	end
end

function Skins.Refresh()
	-- called when a switch turns off: give the original look back
	local P, O = Skins.Paint, Skins.Others
	if not P.Enabled then restoreCharacter(lp.Character) end
	if not O.Enabled then
		for _, plr in ipairs(Players:GetPlayers()) do if plr ~= lp then restoreCharacter(plr.Character) end end
	end
end

function Skins.ApplyPreset(p)
	Skins.Paint.Color, Skins.Paint.Material, Skins.Paint.Transparency = p.color, p.material, p.transparency
	Skins.Paint.Rainbow = false
end

-- copy any Roblox user's avatar onto your own character (client-side)
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

function Skins.Start()
	if conn then return end
	local acc = 0
	conn = RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < 0.1 then return end
		acc = 0
		local ok, err = pcall(step)
		if not ok and Skins.Info ~= "error" then Skins.Info = "error"; warn("[skins] " .. tostring(err)) end
	end)
	-- keep a copied look after respawning
	lp.CharacterAdded:Connect(function()
		if Skins.KeepLook and lastWho then
			task.wait(1.2)
			Skins.CopyUser(lastWho)
		end
	end)
end

function Skins.Destroy()
	if conn then conn:Disconnect(); conn = nil end
	Skins.Paint.Enabled, Skins.Others.Enabled = false, false
	restoreCharacter(lp.Character)
	for _, plr in ipairs(Players:GetPlayers()) do if plr ~= lp then restoreCharacter(plr.Character) end end
	Skins.RestoreLook()
end

return Skins
