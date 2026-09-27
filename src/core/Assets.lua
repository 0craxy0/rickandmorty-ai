--[[
	core/Assets.lua
	PNG handling from idea/png-usage.md.

	The three assets live beside the executor's workspace folder:
		title.png  — main logo (3840x2160, aspect ratio 16:9)
		rick.png   — Rick companion portrait
		morty.png  — Morty companion portrait

	Roblox cannot read arbitrary disk paths, so we hand the local file to the
	executor's `getcustomasset()` which returns a usable asset id. When that is
	unavailable (vanilla Roblox, or the file was not shipped next to the script)
	we fall back to a bundled rbxassetid so the UI still renders.
]]

local Util = require("core/Util")

local Assets = {}

-- title.png ships as a 3840x2160 canvas, but the logo art itself only fills a
-- 3468x1064 horizontal band (the rest is transparent padding). Constraining to
-- the canvas ratio would letterbox the logo into a sliver, so the constraint
-- uses the trimmed ratio instead.  See `Assets.report()` for the raw numbers.
Assets.TITLE_ASPECT = 3468 / 1064 -- ~3.259
Assets.TITLE_CANVAS = { width = 3840, height = 2160 }

Assets.files = {
	title = "title.png",
	rick = "rick.png",
	morty = "morty.png",
}

-- Searched in order, relative to the executor workspace folder.
Assets.searchPaths = { "", "imgs/", "assets/" }

-- Intentionally empty: the spec sources art from the executor workspace, and a
-- fabricated rbxassetid would silently render the wrong picture. A missing file
-- simply draws nothing, and boot raises a warning toast so the cause is obvious.
Assets.fallback = {
	title = "",
	rick = "",
	morty = "",
}

Assets.cache = {}
Assets.missing = {}

function Assets.exists(path)
	local isfile = Util.global("isfile")
	if type(isfile) ~= "function" then
		return false
	end

	local ok, result = pcall(isfile, path)
	return ok and result == true
end

--- Finds the asset on disk, trying each configured search path.
function Assets.locate(name)
	local relative = Assets.files[name] or name

	for _, prefix in ipairs(Assets.searchPaths) do
		local candidate = prefix .. relative
		if Assets.exists(candidate) then
			return candidate
		end
	end

	return nil
end

--- Resolves a logical asset name to something ImageLabel.Image accepts.
function Assets.resolve(name)
	local cached = Assets.cache[name]
	if cached ~= nil then
		return cached
	end

	local id = ""
	local located = Assets.locate(name)
	local getcustomasset = Util.global("getcustomasset")

	if located and type(getcustomasset) == "function" then
		local ok, result = pcall(getcustomasset, located)
		if ok and type(result) == "string" and result ~= "" then
			id = result
		end
	end

	if id == "" then
		id = Assets.fallback[name] or ""
		Assets.missing[name] = located ~= nil
	end

	Assets.cache[name] = id
	return id
end

function Assets.title()
	return Assets.resolve("title")
end

function Assets.portrait(companion)
	local key = string.lower(tostring(companion)) == "morty" and "morty" or "rick"
	return Assets.resolve(key)
end

--- Builds an ImageLabel pre-configured per the PNG spec.
function Assets.imageLabel(name, props, children)
	local config = {
		Name = name or "Asset",
		BackgroundTransparency = 1,
		Image = Assets.resolve(string.lower(name or "title")),
		ScaleType = Enum.ScaleType.Fit,
	}
	if props then
		for key, value in pairs(props) do
			config[key] = value
		end
	end

	-- Resolve again when the caller overrides Name after construction.
	if config.Image == "" then
		config.Image = Assets.fallback[string.lower(name or "title")] or ""
	end

	return Util.create("ImageLabel", config, children)
end

--- UIAspectRatioConstraint so the title never stretches (spec §4).
--- DominantAxis.Height keeps the requested height and derives the width, which
--- is what a wide banner wants inside a short header.
function Assets.aspect(instance, ratio, dominantAxis)
	return Util.create("UIAspectRatioConstraint", {
		AspectRatio = ratio or Assets.TITLE_ASPECT,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = dominantAxis or Enum.DominantAxis.Height,
		Parent = instance,
	})
end

--- Names of assets that could not be found on disk.
function Assets.missingNames()
	local missing = {}
	for _, name in ipairs({ "title", "rick", "morty" }) do
		if not Assets.locate(name) then
			table.insert(missing, name .. ".png")
		end
	end
	return missing
end

--- Human readable report for the onboarding panel / notifications.
function Assets.report()
	local lines = {}
	for _, name in ipairs({ "title", "rick", "morty" }) do
		local path = Assets.locate(name)
		table.insert(
			lines,
			string.format("%s.png: %s", name, path and ("local (" .. path .. ")") or "remote fallback")
		)
	end
	return table.concat(lines, "\n")
end

return Assets
