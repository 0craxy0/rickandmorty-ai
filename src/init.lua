--[[
	init.lua
	Entry point for the Rick & Morty AI Executor.

	Boot order:
	  1. re-run safety: unload any previous instance
	  2. load persisted config (companion, provider, keys, onboarding flag)
	  3. build the ScreenGui, notifications, quick menu and dashboard
	  4. first run: start the onboarding tour; otherwise stay collapsed to the anchor

	Public API (also exposed as `getgenv().RickMortyAI`):
	  :Open()            :Close()          :Toggle()
	  :ToggleQuickMenu() :SetCompanion(n)  :Unload()
]]

local Assets = require("core/Assets")
local Http = require("core/Http")
local Notify = require("ui/Notify")
local Palette = require("core/Palette")
local State = require("core/State")
local Tutorial = require("ui/Tutorial")
local Typewriter = require("core/Typewriter")
local Util = require("core/Util")

local Dashboard = require("ui/Dashboard")
local QuickMenu = require("ui/QuickMenu")

local app = {}

app.version = "1.0.0"
app.gui = nil
app.dashboard = nil
app.quickMenu = nil
app.tutorial = nil
app.sidebar = nil

-- Small helpers ---------------------------------------------------------------

local function environment()
	return Util.environment()
end

-- API -------------------------------------------------------------------------

function app.notify(title, body, variant)
	return Notify.toast({
		Title = title,
		Body = body,
		Variant = variant or "info",
	})
end

function app.Open()
	if app.dashboard then
		app.dashboard:setVisible(true)
		app.dashboard:refresh()
	end
end

function app.Close()
	if app.dashboard then
		app.dashboard:setVisible(false)
	end
end

function app.Toggle()
	if app.dashboard then
		app.dashboard:toggle()
	end
end

function app.ToggleQuickMenu()
	if app.quickMenu then
		app.quickMenu:toggle()
	end
end

function app.SetCompanion(name)
	State.setCompanion(name)
	app.OnCompanionChanged(name)
end

--- Re-skins every companion surface after a Rick/Morty switch.
function app.OnCompanionChanged(name)
	if app.dashboard then
		app.dashboard:refresh()
	end

	-- Stay quiet while the onboarding tour is driving the switch itself.
	if app.notify and name and not app.tutorial then
		local theme = Palette.character(name)
		app.notify("Companion switched", theme.label .. " // " .. theme.tagline, "info")
	end
end

--- Restores an archived conversation into the chat pane.
function app.OnHistoryRestored()
	if app.dashboard then
		app.dashboard:setTab("Chat")
		app.dashboard.panels.Chat:render()
	end
end

function app.Unload()
	if app.quickMenu then
		pcall(function()
			app.quickMenu:destroy()
		end)
		app.quickMenu = nil
	end

	Typewriter.destroy()

	if app.dashboard then
		pcall(function()
			app.dashboard:destroy()
		end)
		app.dashboard = nil
	end

	if app.gui then
		pcall(function()
			app.gui:Destroy()
		end)
		app.gui = nil
	end

	local env = environment()
	if env.RickMortyAI == app then
		env.RickMortyAI = nil
	end

	app.unloaded = true
end

-- Boot ------------------------------------------------------------------------

function app.init()
	-- Only one instance at a time.
	local env = environment()
	local existing = env.RickMortyAI
	if existing and existing ~= app and type(existing.Unload) == "function" then
		pcall(existing.Unload)
	end

	State.load()

	local parent = Util.guiParent()
	if not parent then
		warn("[RickMortyAI] no PlayerGui yet; aborting.")
		return app
	end

	app.gui = Util.create("ScreenGui", {
		Name = "RickMortyAI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	})

	Notify.setup(app.gui)

	app.quickMenu = QuickMenu.new(app.gui, app)
	app.dashboard = Dashboard.new(app.gui, app)

	if not State.data.onboarded then
		app.dashboard:setVisible(true)

		app.tutorial = Tutorial.start(app.gui, app, function()
			app.tutorial = nil
			app.notify(
				"Setup complete",
				"Press ';' anywhere for the quick menu, or click the AI CONSOLE anchor to reopen this window.",
				"ok"
			)
		end)
	else
		app.dashboard:setVisible(false)
	end

	-- Warn when the PNGs were not shipped beside the script.
	if Util.isExecutor() then
		local missing = Assets.missingNames()
		if #missing > 0 then
			app.notify(
				"Artwork not found",
				"Missing " .. table.concat(missing, ", ") .. ". Drop them beside the executor's workspace folder (or in imgs/) and re-run.",
				"warn"
			)
		end
	end

	local transport = Http.transportName()
	app.notify(
		"Rick & Morty AI Executor v" .. app.version,
		"Press ';' for the quick menu."
			.. "\nTransport: "
			.. transport
			.. "\nCompanion: "
			.. State.companion()
			.. " // "
			.. State.provider(),
		Http.available() and "info" or "warn"
	)

	env.RickMortyAI = app
	app.unloaded = false

	return app
end

app.init()

return app
