-- Skins tab: paint yourself / other players, presets, copy a Roblox avatar onto you (client-side only).
local UIS = game:GetService("UserInputService")
local Skins = __import("visuals/skins")

return function(ctx)
	local win, safe, cycle = ctx.win, ctx.safe, ctx.cycle
	local tSkin = win:Tab("Skins", { Section = "Combat", Icon = 13 })
	local lSkinNote = tSkin:Label({ Name = "Only you see these", Value = "client-side" })
	-- one set of controls for "my skin" and for "other players" (S = the settings table of that skin)
	local function skinModule(title, S, others)
		local mod
		local ui = {}
		mod = tSkin:Module({ Name = title, Default = false, Callback = function(on) S.Enabled = on; Skins.Refresh() end })
		if others then
			ui.team = mod:Toggle({ Name = "Team colours (police blue, fire red ...)", Default = S.TeamColors, Callback = function(v) S.TeamColors = v; Skins.Refresh() end })
		end
		local names = { "Pick a preset..." }
		for _, n in ipairs(Skins.PresetNames) do names[#names + 1] = n end
		-- after a preset, every control shows the preset's values (otherwise the next autosave would store the old ones)
		local function sync()
			ui.c1:Set(S.Color, true); ui.c2:Set(S.Color2, true); ui.mode:Set(S.Mode, true); ui.mat:Set(S.Material, true); ui.tr:Set(S.Transparency, true)
			ui.glow:Set(S.Outline, true); ui.glowCol:Set(S.OutlineColor, true)
			if ui.team then ui.team:Set(S.TeamColors, true) end
		end
		ui.preset = mod:Choice({ Name = "Preset", NoSave = true, Options = names, Default = names[1], Callback = function(v)
			if v == names[1] then return end
			local p = Skins.ApplyPreset(v, S)
			if p then
				sync()
				if not mod:Get() then mod:Set(true) end
				win:Notify("Skin: " .. v, 2)
			end
		end })
		mod:Section("Look")
		ui.c1 = mod:ColorPicker({ Name = "Colour", Default = S.Color, Callback = function(c) S.Color = c; if ui.team then S.TeamColors = false; ui.team:Set(false, true) end; Skins.Refresh() end })
		ui.c2 = mod:ColorPicker({ Name = "Second colour", Default = S.Color2, Callback = function(c) S.Color2 = c; Skins.Refresh() end })
		ui.mode = mod:Choice({ Name = "Pattern", Options = Skins.Modes, Default = S.Mode, Callback = function(v) S.Mode = v; Skins.Refresh() end })
		ui.mat = mod:Choice({ Name = "Material", Options = Skins.Materials, Default = S.Material, Callback = function(v) S.Material = v; Skins.Refresh() end })
		ui.tr = mod:Slider({ Name = "See-through", Min = 0, Max = 0.95, Step = 0.05, Default = S.Transparency, Callback = function(v) S.Transparency = v; Skins.Refresh() end })
		mod:Slider({ Name = "Animation speed", Min = 0.2, Max = 4, Step = 0.1, Default = S.Speed, Suffix = "x", Callback = function(v) S.Speed = v end })
		mod:Section("Glow")
		ui.glow = mod:Toggle({ Name = "Outline glow", Default = S.Outline, Callback = function(v) S.Outline = v; Skins.Refresh() end })
		ui.glowCol = mod:ColorPicker({ Name = "Glow colour", Default = S.OutlineColor, Callback = function(c) S.OutlineColor = c; Skins.Refresh() end })
		mod:Toggle({ Name = "Glow shows through walls", Default = S.SeeThrough, Callback = function(v) S.SeeThrough = v; Skins.Refresh() end })
		mod:Section("What gets painted")
		mod:Toggle({ Name = "Hats / accessories too", Default = S.Accessories, Callback = function(v) S.Accessories = v; Skins.Refresh() end })
		mod:Toggle({ Name = "Hide shirts and pants (they cover the paint)", Default = S.HideClothes, Callback = function(v) S.HideClothes = v; Skins.Refresh() end })
		mod:Toggle({ Name = "Hide the face", Default = S.HideFace, Callback = function(v) S.HideFace = v; Skins.Refresh() end })
		return mod
	end
	local mPaint = skinModule("My skin (paint my character)", Skins.Paint, false)
	local mOthers = skinModule("Paint other players", Skins.Others, true)

	tSkin:Section("Copy a Roblox avatar onto me")
	local skinName = ""
	tSkin:TextBox({ Name = "Username or user id", Placeholder = "e.g. Roblox", NoSave = true, Callback = function(t) skinName = t or "" end })
	tSkin:Button({ Name = "Apply that avatar to my character", NoSave = true, Callback = function()
		local ok, why = Skins.CopyUser(skinName)
		win:Notify(ok and "Avatar applied (only you see it)" or ("Could not apply: " .. tostring(why)), 3)
	end })
	tSkin:Toggle({ Name = "Keep the avatar after respawning", Default = Skins.KeepLook, Callback = function(v) Skins.KeepLook = v end })
	tSkin:Button({ Name = "Back to my own avatar", NoSave = true, Callback = function() Skins.RestoreLook(); win:Notify("Original avatar restored", 2) end })
	safe("skins", Skins.Start)

end
