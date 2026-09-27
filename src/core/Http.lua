--[[
	core/Http.lua
	Network transport from idea/backend.md §3.

	Roblox's HttpService refuses most third-party domains, so we prefer the
	executor's privileged request function (`request`, `http_request`,
	`syn.request`, ...) and only fall back to `HttpService:RequestAsync`.

	Every call returns a normalised result table so callers never branch on
	which transport actually ran:

		{ ok = boolean, status = number, body = string, error = string? }
]]

local HttpService = game:GetService("HttpService")

local Util = require("core/Util")

local Http = {}

Http.TIMEOUT = 60

--- Picks whichever privileged requester this executor exposes.
local function requester()
	local env = Util.environment()

	local candidates = {
		env.request,
		env.http_request,
		env.syn and env.syn.request,
		env.http and env.http.request,
		env.krnl and env.krnl.request,
		env.fluxus and env.fluxus.request,
		env.electron and env.electron.request,
		env.volt and env.volt.request,
	}

	for _, candidate in ipairs(candidates) do
		if type(candidate) == "function" then
			return candidate
		end
	end

	for _, name in ipairs({ "request", "http_request" }) do
		local fn = Util.global(name)
		if type(fn) == "function" then
			return fn
		end
	end

	return nil
end

function Http.encode(value)
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(value)
	end)

	if not ok then
		return nil, tostring(encoded)
	end

	return encoded
end

function Http.decode(text)
	if type(text) ~= "string" or Util.trim(text) == "" then
		return nil
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(text)
	end)

	if not ok then
		return nil
	end

	return decoded
end

function Http.encodeQuery(params)
	local parts = {}
	for key, value in pairs(params or {}) do
		table.insert(parts, string.format("%s=%s", key, tostring(value)))
	end
	return table.concat(parts, "&")
end

--- Perform a request. `options` = { Url, Method, Headers, Body }.
function Http.request(options)
	local url = options.Url or options.url
	local method = options.Method or options.method or "GET"
	local headers = options.Headers or options.headers or {}
	local body = options.Body or options.body

	if body == nil and options.json ~= nil then
		body = Http.encode(options.json)
	end

	if type(body) == "table" then
		body = Http.encode(body)
	end

	local fn = requester()
	if fn then
		local ok, response = pcall(fn, {
			Url = url,
			Method = method,
			Headers = headers,
			Body = body,
		})

		if ok and type(response) == "table" then
			local status = response.StatusCode or response.Status or 0
			return {
				ok = status >= 200 and status < 300,
				status = status,
				body = response.Body or response.body or "",
				error = nil,
			}
		end

		if not ok then
			return { ok = false, status = 0, body = "", error = tostring(response) }
		end
	end

	-- Fallback: only works for domains whitelisted in game settings.
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = method,
			Headers = headers,
			Body = body,
		})
	end)

	if ok and type(response) == "table" then
		return {
			ok = response.Success == true,
			status = response.StatusCode or 0,
			body = response.Body or "",
			error = response.Success and nil or response.StatusMessage,
		}
	end

	return {
		ok = false,
		status = 0,
		body = "",
		error = "No privileged HTTP transport available ("
			.. tostring(response)
			.. "). Enable HTTP requests or run inside an executor.",
	}
end

--- True when the executor exposes a usable privileged transport.
function Http.available()
	return requester() ~= nil
end

function Http.transportName()
	local fn = requester()
	if not fn then
		return "HttpService (whitelisted domains only)"
	end

	local env = Util.environment()
	if env.request == fn then
		return "request"
	end
	if env.http_request == fn then
		return "http_request"
	end
	if env.syn and env.syn.request == fn then
		return "syn.request"
	end

	return "privileged request"
end

return Http
