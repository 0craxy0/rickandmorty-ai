--[[
	core/Cowork.lua
	Cowork mode filesystem bridge from idea/backend.md §2.

	Sequence:
	  1. create/verify the /rick_morty_bridge/ folder in the executor workspace
	  2. write server.js + index.html (the external high-fidelity interface)
	  3. write launch_bridge.bat (Windows) / launch_bridge.sh (Mac/Linux)
	  4. write config.json so the bridge knows the active provider/keys
	  5. hand the user a notification pointing at the launcher

	The bridge serves http://localhost:7896 and talks to the configured
	provider directly from Node, so no Roblox HTTP restrictions apply.
]]

local Http = require("core/Http")
local Providers = require("core/Providers")
local State = require("core/State")
local Util = require("core/Util")

local Cowork = {}

Cowork.DIR = "rick_morty_bridge"
Cowork.PORT = 7896
Cowork.URL = "http://localhost:7896"

Cowork.launchers = {
	windows = "launch_bridge.bat",
	posix = "launch_bridge.sh",
}

--- Raw text assets inlined by build.js from /bridge.
function Cowork.assets()
	local ok, assets = pcall(require, "bundle/assets")
	if ok and type(assets) == "table" then
		return assets
	end

	return {}
end

function Cowork.available()
	return type(Util.global("writefile")) == "function"
end

function Cowork.path(relative)
	return Cowork.DIR .. "/" .. relative
end

function Cowork.ensureFolder()
	local isfolder = Util.global("isfolder")
	local makefolder = Util.global("makefolder")

	if type(isfolder) == "function" then
		local ok, exists = pcall(isfolder, Cowork.DIR)
		if ok and exists then
			return true
		end
	end

	if type(makefolder) == "function" then
		pcall(makefolder, Cowork.DIR)
		return true
	end

	return false
end

function Cowork.write(relative, contents)
	local writefile = Util.global("writefile")
	if type(writefile) ~= "function" then
		return false, "writefile is unavailable in this environment."
	end

	local path = Cowork.path(relative)
	local ok, err = pcall(writefile, path, contents)
	if not ok then
		return false, tostring(err)
	end

	return true, path
end

--- Provider wiring for the Node bridge, mirroring the Lua provider matrix.
function Cowork.config()
	local providerId = State.provider()
	local provider = Providers.get(providerId)

	return Http.encode({
		provider = providerId,
		style = provider.style,
		model = State.model(provider.model),
		url = State.data.urls[providerId] or provider.url,
		apiKey = State.apiKey(providerId),
		companion = State.companion(),
		persona = require("core/Persona").systemMessage(State.companion()),
		port = Cowork.PORT,
	})
end

--- Writes the whole bridge. Returns (ok, filesWrittenOrError).
function Cowork.build()
	if not Cowork.available() then
		return false, "This executor does not expose writefile(), so the Cowork bridge cannot be generated."
	end

	Cowork.ensureFolder()

	local assets = Cowork.assets()
	local written = {}
	local failures = {}

	local payload = {
		{ Cowork.launchers.windows, assets["bridge/launch_bridge.bat"] },
		{ Cowork.launchers.posix, assets["bridge/launch_bridge.sh"] },
		{ "server.js", assets["bridge/server.js"] },
		{ "index.html", assets["bridge/index.html"] },
		{ "README.txt", assets["bridge/README.txt"] },
		{ "config.json", Cowork.config() },
	}

	for _, entry in ipairs(payload) do
		local name, contents = entry[1], entry[2]

		if type(contents) == "string" and contents ~= "" then
			local ok, pathOrError = Cowork.write(name, contents)
			if ok then
				table.insert(written, pathOrError)
			else
				table.insert(failures, name .. ": " .. tostring(pathOrError))
			end
		else
			table.insert(failures, name .. ": missing bundled asset")
		end
	end

	-- Best effort: make the shell launcher executable on POSIX hosts.
	local run = Util.global("run") or Util.global("shell")
	if type(run) == "function" then
		pcall(run, string.format('chmod +x "%s"', Cowork.path(Cowork.launchers.posix)))
	end

	if #written == 0 then
		return false, table.concat(failures, "\n")
	end

	return true, written
end

--- Human-readable instructions for the notification panel.
function Cowork.instructions()
	local lines = {
		"1. Open your executor's workspace folder.",
		"2. Enter the " .. Cowork.DIR .. " directory.",
		"3. Double-click " .. Cowork.launchers.windows .. " (Windows) or run " .. Cowork.launchers.posix .. ".",
		"4. The dashboard opens at " .. Cowork.URL .. ".",
		"Node.js 18+ must be installed for the bridge to start.",
	}

	return table.concat(lines, "\n")
end

function Cowork.status()
	if not Cowork.available() then
		return "unavailable (no writefile)"
	end

	local isfolder = Util.global("isfolder")
	if type(isfolder) == "function" then
		local ok, exists = pcall(isfolder, Cowork.DIR)
		if ok and exists then
			return "ready in " .. Cowork.DIR
		end
	end

	return "not generated"
end

return Cowork
