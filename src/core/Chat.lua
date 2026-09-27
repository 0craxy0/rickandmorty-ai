--[[
	core/Chat.lua
	Conversation pipeline: persona injection -> provider template -> transport
	-> response parsing -> history bookkeeping.

	The visible transcript only ever contains user/assistant turns; the system
	directive stays hidden (idea/backend.md §1).
]]

local CodeRunner = require("core/CodeRunner")
local Http = require("core/Http")
local Persona = require("core/Persona")
local Providers = require("core/Providers")
local State = require("core/State")
local Util = require("core/Util")

local Chat = {}

Chat.busy = false
Chat.lastError = nil

--- Builds the outbound request without sending it (used by the Code pane preview).
function Chat.compile(prompt, history)
	local providerId = State.provider()
	local provider = Providers.get(providerId)
	local packed = Persona.buildMessages(State.companion(), history or State.history, prompt)

	return {
		provider = providerId,
		url = State.data.urls[providerId] or provider.url,
		headers = Providers.buildHeaders(providerId, State.apiKey(providerId)),
		body = Providers.buildBody(providerId, {
			messages = packed.messages,
			system = packed.system,
			prompt = prompt,
			model = State.model(provider.model),
		}),
	}
end

--[[
	Sends `prompt` to the active provider.

	handlers = {
		onUser    = function(text)
		onDelta   = function(chunk)   -- received assistant text (single shot)
		onDone    = function(text)    -- parsed assistant reply
		onError   = function(message)
		onFinish  = function()        -- always runs, success or failure
	}
]]
function Chat.send(prompt, handlers)
	handlers = handlers or {}

	if Chat.busy then
		if handlers.onError then
			handlers.onError("A request is already in flight.")
		end
		return nil
	end

	if type(prompt) ~= "string" or Util.trim(prompt) == "" then
		if handlers.onError then
			handlers.onError("Prompt is empty.")
		end
		return nil
	end

	Chat.busy = true
	Chat.lastError = nil

	State.pushMessage("user", prompt)
	if handlers.onUser then
		handlers.onUser(prompt)
	end

	local handle = {
		done = false,
		cancelled = false,
		prompt = prompt,
	}

	function handle.cancel()
		handle.cancelled = true
	end

	function handle.await()
		while not handle.done do
			task.wait()
		end
	end

	task.spawn(function()
		local compiled = Chat.compile(prompt)

		local finish = function()
			Chat.busy = false
			handle.done = true
			if handlers.onFinish then
				handlers.onFinish()
			end
		end

		local fail = function(message)
			Chat.lastError = message
			if not handle.cancelled and handlers.onError then
				handlers.onError(message)
			end
			finish()
		end

		if not Http.available() then
			fail(
				"No HTTP transport available. Run inside an executor that provides "
					.. "`request`/`http_request`, or enable HTTP requests in game settings."
			)
			return
		end

		local encodedBody = Http.encode(compiled.body)
		if not encodedBody then
			fail("Could not encode the request payload.")
			return
		end

		State.bumpRequests()

		local result = Http.request({
			Url = compiled.url,
			Method = "POST",
			Headers = compiled.headers,
			Body = encodedBody,
		})

		if handle.cancelled then
			finish()
			return
		end

		if not result.ok then
			local detail = result.error or result.body or "unknown error"
			fail(string.format("%s (HTTP %s): %s", compiled.provider, tostring(result.status), tostring(detail)))
			return
		end

		local text, parseError = Providers.parse(compiled.provider, result.body)
		if not text then
			fail(parseError or "Unparseable provider response.")
			return
		end

		State.pushMessage("assistant", text)

		if handlers.onDelta then
			handlers.onDelta(text)
		end
		if handlers.onDone then
			handlers.onDone(text)
		end

		finish()
	end)

	return handle
end

--[[
	Convenience for the semicolon quick menu and the Code pane:
	send a prompt, execute any returned Lua, report through `log`.
]]
function Chat.sendAndRun(prompt, log, handlers)
	handlers = handlers or {}
	local logger = log or function() end

	return Chat.send(prompt, {
		onUser = function(text)
			logger("> " .. text, "user")
			if handlers.onUser then
				handlers.onUser(text)
			end
		end,
		onDone = function(text)
			if handlers.onReply then
				handlers.onReply(text)
			end

			if CodeRunner.looksLikeCode(text) then
				local ok, output = CodeRunner.execute(text)
				if ok then
					logger(output ~= "" and ("[executed] " .. output) or "[executed] script finished", "ok")
				else
					logger("[execution error] " .. tostring(output), "error")
				end
				if handlers.onExecuted then
					handlers.onExecuted(ok, output)
				end
			else
				logger("[no executable block] reply shown in chat only", "warn")
			end
		end,
		onError = function(message)
			logger("[error] " .. tostring(message), "error")
			if handlers.onError then
				handlers.onError(message)
			end
		end,
		onFinish = handlers.onFinish,
	})
end

return Chat
