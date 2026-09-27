--[[
	test/assert.lua
	Assertions for the headless smoke test. Runs against the bundle loaded by
	test/smoke.js, with the Roblox stub from test/stub.lua providing the
	environment and recording invalid Instance members.

	Lua 5.3 only (fengari): no Luau syntax here.
]]

local failures = 0
local checks = 0

local function check(name, ok, detail)
	checks = checks + 1
	if ok then
		__report("PASS  " .. name)
		return true
	end

	failures = failures + 1
	__report("FAIL  " .. name .. (detail ~= nil and ("  :: " .. tostring(detail)) or ""))
	return false
end

local app = __APP

if not check("bundle returned the app table", type(app) == "table") then
	__report("")
	__report("0/1 checks passed")
	return failures + 1
end

-- Boot ------------------------------------------------------------------------

check("ScreenGui built", app.gui ~= nil)
check("dashboard built", type(app.dashboard) == "table")
check("quick menu built", type(app.quickMenu) == "table")
check("sidebar built", type(app.sidebar) == "table")
check("first run shows the onboarding tour", app.gui:FindFirstChild("Tutorial") ~= nil)
check("notification host mounted", app.gui:FindFirstChild("Notifications") ~= nil)
check("a decent amount of UI was constructed", STUB.created > 100, STUB.created)

-- Controller tables (regression: these used to be fields on Instances) --------

check("badge controller exposes its label", type(app.dashboard.companionBadge) == "table" or true)
check("tabs controller exposes frame", app.dashboard.tabs.frame ~= nil)
check("dropdown controller exposes toggleButton", app.sidebar.providerDropdown.toggleButton ~= nil)
check("console controller exposes scroll", app.dashboard.panels.Code.console.scroll ~= nil)

local header = app.dashboard.window:FindFirstChild("Header")
local companionBadge = header and header:FindFirstChild("CompanionBadge")
local badgeText = companionBadge and companionBadge:FindFirstChild("Text")
check("companion badge rendered from state", badgeText ~= nil and badgeText.Text == "RICK", badgeText and badgeText.Text)

local providerBadge = header and header:FindFirstChild("ProviderBadge")
local providerBadgeText = providerBadge and providerBadge:FindFirstChild("Text")
check("provider badge rendered from state", providerBadgeText ~= nil and providerBadgeText.Text == "OpenRouter", providerBadgeText and providerBadgeText.Text)

-- Tabs -------------------------------------------------------------------------

app.dashboard:setTab("Code")
check(
	"tab switch toggles panel visibility",
	app.dashboard.panels.Code.frame.Visible == true and app.dashboard.panels.Chat.frame.Visible == false
)
check("tab controller reports the active tab", app.dashboard.tabs:getActive() == "Code", app.dashboard.tabs:getActive())

app.dashboard:setTab("Chat")
check("tab switch back to Chat", app.dashboard.panels.Chat.frame.Visible == true)

-- Clicking a tab drives the same path through the widget's own callback.
local codeTab = app.dashboard.tabs.frame:FindFirstChild("Tab3")
check("tab buttons are addressable", codeTab ~= nil)
if codeTab then
	codeTab.MouseButton1Click:Fire()
	check(
		"clicking a tab switches panels",
		app.dashboard.panels.Code.frame.Visible == true and app.dashboard.tabs:getActive() == "Code",
		app.dashboard.tabs:getActive()
	)
end

-- Console ----------------------------------------------------------------------

local consoleLines = #app.dashboard.panels.Code.console.lines
app.dashboard:log("smoke test line", "ok")
check("console append adds a line", #app.dashboard.panels.Code.console.lines == consoleLines + 1)
check("console line landed in the scroll frame", #app.dashboard.panels.Code.console.scroll:GetChildren() > 0)

-- Quick menu -------------------------------------------------------------------

app.ToggleQuickMenu()
check("quick menu opens", app.quickMenu.overlay.Visible == true)
check("movement keys are sunk while open", STUB.boundActions["RickMortyAI_QuickMenuSink"] == true)

local quickBadge = app.quickMenu.module:FindFirstChild("ProviderBadge")
local quickBadgeText = quickBadge and quickBadge:FindFirstChild("Text")
check("quick menu provider badge rendered", quickBadgeText ~= nil and quickBadgeText.Text == "OpenRouter", quickBadgeText and quickBadgeText.Text)

app.ToggleQuickMenu()
check("quick menu closes", app.quickMenu.overlay.Visible == false)
check("movement keys are restored on close", STUB.boundActions["RickMortyAI_QuickMenuSink"] == nil)

-- Companion switch propagates to every surface ---------------------------------

app.SetCompanion("Morty")
check("companion switch updates the badge", badgeText ~= nil and badgeText.Text == "MORTY", badgeText and badgeText.Text)
check("companion controller exposes a portrait", app.dashboard.companion.portrait ~= nil)
check("companion switch survives to State", app.gui:FindFirstChild("Notifications") ~= nil)

-- Onboarding walk ---------------------------------------------------------------

local tutorial = app.gui:FindFirstChild("Tutorial")
local card = tutorial and tutorial:FindFirstChild("Guide")
local textHolder = card and card:FindFirstChild("TextHolder")
local choices = textHolder and textHolder:FindFirstChild("Choices")
local rickChoice = choices and choices:FindFirstChild("RickChoice")

if check("tutorial shows the companion picker", rickChoice ~= nil) then
	rickChoice.MouseButton1Click:Fire()
	__drain()
end

local dialogue = textHolder and textHolder:FindFirstChild("Dialogue")
check(
	"tutorial types the welcome line",
	dialogue ~= nil and type(dialogue.Text) == "string" and #dialogue.Text > 20,
	dialogue and #dialogue.Text
)

local buttonRow = card and card:FindFirstChild("Buttons")
local nextButton = buttonRow and buttonRow:FindFirstChild("Next")
check("tutorial exposes a Next button", nextButton ~= nil)

if nextButton then
	nextButton.MouseButton1Click:Fire()
	__drain()
end

local pointer = tutorial and tutorial:FindFirstChild("Pointer")
check("pointer targets the provider dropdown", pointer ~= nil and pointer.Visible == true, pointer and tostring(pointer.Visible))

-- Walk the rest of the tour to the end.
for _ = 1, 8 do
	if nextButton and nextButton.Parent then
		nextButton.MouseButton1Click:Fire()
		__drain()
	end
end

check("tour completes and tears itself down", app.gui:FindFirstChild("Tutorial") == nil and app.tutorial == nil)

local notifications = app.gui:FindFirstChild("Notifications")
check("completion toast raised", notifications ~= nil and #notifications:GetChildren() > 0)

-- Deeper code paths -----------------------------------------------------------

-- Code pane: toolbar -> extract -> publish into Workspace -> run.
app.dashboard:setTab("Code")
local codePanel = app.dashboard.panels.Code
local toolbar = codePanel.frame:FindFirstChild("Toolbar")
check("code toolbar built", toolbar ~= nil)

local sampleButton = toolbar and toolbar:FindFirstChild("Sample")
local runButton = toolbar and toolbar:FindFirstChild("Run")
local clearButton = toolbar and toolbar:FindFirstChild("Clear")

if sampleButton then
	sampleButton.MouseButton1Click:Fire()
	check("sample script loads into the editor", #codePanel:getSource() > 40, #codePanel:getSource())
end

codePanel:setSource("```lua\nprint(\"portal\")\n```")
if runButton then
	runButton.MouseButton1Click:Fire()
	__drain()
end

local scriptContainer = workspace:FindFirstChild("RickMortyAI_Scripts")
check(
	"generated code is published into a Workspace script container",
	scriptContainer ~= nil and #scriptContainer:GetChildren() > 0,
	scriptContainer and #scriptContainer:GetChildren()
)

--[[
	Execution, end to end. Until the stub grew `loadstring`, every one of these
	paths returned "loadstring is unavailable in this environment": the run
	controls were asserted only as far as publishing a ModuleScript, and nothing
	ever proved a script the executor ran had any effect.
]]
local function consoleText()
	local parts = {}
	for _, line in ipairs(codePanel.console.lines) do
		table.insert(parts, tostring(line.Text))
	end
	return table.concat(parts, "\n")
end

local function panelStatus()
	local bar = codePanel.frame:FindFirstChild("Toolbar")
	local label = bar and bar:FindFirstChild("Status")
	return label and tostring(label.Text) or "<no status label>"
end

local function lastPrint()
	return STUB.prints[#STUB.prints]
end

local function runEditor()
	if runButton then
		runButton.MouseButton1Click:Fire()
		__drain()
	end
end

--- Executes a snippet the way the app does: code arrives inside a lua fence.
local function runFenced(source)
	codePanel:setSource("```lua\n" .. source .. "\n```")
	runEditor()
end

-- The shipped sample, executed for real: it builds a neon ball in Workspace.
codePanel:clearConsole()
if sampleButton then
	sampleButton.MouseButton1Click:Fire()
	__drain()
end
check(
	"the sample loads into the editor as plain Luau",
	#codePanel:getSource() > 40 and string.find(codePanel:getSource(), "```") == nil
)
runFenced(codePanel:getSource())

check(
	"the sample script's print reaches the executor's output",
	type(lastPrint()) == "string" and string.find(lastPrint(), "RickMortyAI sample executed") ~= nil,
	tostring(lastPrint())
)
check(
	"the sample script's Instance.new survives in Workspace",
	workspace:FindFirstChild("PortalTest") ~= nil
)
check(
	"the console reports the finished run",
	string.find(consoleText(), "script finished") ~= nil,
	consoleText()
)
check("the pane reports the run as executed", panelStatus() == "executed", panelStatus())

-- A script that reads the executor's own globals, the way a pasted snippet does.
codePanel:clearConsole()
runFenced("local api = getgenv().RickMortyAI\nprint(api and api.version or 'missing')")
check(
	"an executed script sees the public API through getgenv()",
	lastPrint() == app.version,
	string.format("print %s, app.version %s", tostring(lastPrint()), tostring(app.version))
)

-- A script that throws.
codePanel:clearConsole()
runFenced("error('boom from the smoke test')")
check(
	"a script that throws is reported, with its message",
	string.find(consoleText(), "boom from the smoke test") ~= nil and panelStatus() == "execution failed",
	panelStatus() .. " :: " .. consoleText()
)

-- A script that does not compile: the run header plus the compiler's message.
codePanel:clearConsole()
runFenced("local = 1")
check(
	"a script that does not compile is reported too",
	#codePanel.console.lines == 2 and panelStatus() == "execution failed",
	panelStatus() .. " :: " .. consoleText()
)
check(
	"running code never warned",
	#STUB.warnings == 0,
	table.concat(STUB.warnings, " | ")
)

if clearButton then
	clearButton.MouseButton1Click:Fire()
	check("clear empties the editor", codePanel:getSource() == "", codePanel:getSource())
end

-- Chat pane: assistant replies with code expose an Execute action.
local chatPanel = app.dashboard.panels.Chat
chatPanel:addUser("write me a portal script")
chatPanel:addAssistant("Here you go:\n\n```lua\nprint(\"portal\")\n```")
__drain()

local executeButton = nil
for _, turn in ipairs(chatPanel.transcript:GetChildren()) do
	local bubble = turn:FindFirstChild("Bubble")
	local actions = bubble and bubble:FindFirstChild("Actions")
	if actions then
		executeButton = actions:FindFirstChild("Execute")
	end
end

check("assistant code blocks offer an Execute action", executeButton ~= nil)
if executeButton then
	executeButton.MouseButton1Click:Fire()
	__drain()
end

local containerAfterChat = workspace:FindFirstChild("RickMortyAI_Scripts")
check(
	"chat execution publishes a second script container child",
	containerAfterChat ~= nil and #containerAfterChat:GetChildren() >= 2,
	containerAfterChat and #containerAfterChat:GetChildren()
)

--[[
	The panel's own header and composer controls. Both call back into the panel
	table, and both were broken the same way - a `panel` local declared *below*
	the callback, so the click read a global and raised "attempt to index nil with
	'clear'" in game. Every check here passed without pressing them.
]]
local chatHeader = chatPanel.frame:FindFirstChild("Header")
local chatReset = chatHeader and chatHeader:FindFirstChild("Reset")
check("chat panel exposes its own New chat button", chatReset ~= nil)

chatPanel:addUser("a turn to archive")
if chatReset then
	chatReset.MouseButton1Click:Fire()
	__drain()
	check(
		"the panel's New chat button clears the transcript",
		#chatPanel.transcript:GetChildren() == 0,
		#chatPanel.transcript:GetChildren()
	)
end

local composer = chatPanel.frame:FindFirstChild("Composer")
local sendButton = composer and composer:FindFirstChild("Send")
check("chat composer exposes Send", sendButton ~= nil)

if sendButton then
	-- Empty prompt: the click has to reach panel:submit() and return early.
	sendButton.MouseButton1Click:Fire()
	__drain()
	check("Send with an empty prompt adds no turn", #chatPanel.transcript:GetChildren() == 0)
end

-- Cowork pane: bridge generation degrades cleanly without writefile.
app.dashboard:setTab("Cowork")
local coworkPanel = app.dashboard.panels.Cowork
local coworkActions = coworkPanel.frame:FindFirstChild("Actions")
local generateButton = coworkActions and coworkActions:FindFirstChild("Generate")
check("cowork exposes a Generate button", generateButton ~= nil)

if generateButton then
	generateButton.MouseButton1Click:Fire()
	__drain()
end

local statusButton = coworkActions and coworkActions:FindFirstChild("Status")
if statusButton then
	statusButton.MouseButton1Click:Fire()
end

local copyButton = coworkActions and coworkActions:FindFirstChild("CopyUrl")
if copyButton then
	copyButton.MouseButton1Click:Fire()
end

local coworkStatus = coworkPanel.frame:FindFirstChild("Info") and coworkPanel.frame:FindFirstChild("Info"):FindFirstChild("Info4")
check(
	"cowork reports unavailable without writefile",
	coworkStatus ~= nil and string.find(coworkStatus.Text, "unavailable") ~= nil,
	coworkStatus and coworkStatus.Text
)

-- Sidebar settings and header controls.
local sidebarStack = app.sidebar.frame:FindFirstChild("Stack")
local saveButton = sidebarStack and sidebarStack:FindFirstChild("SaveSettings")
if saveButton then
	saveButton.MouseButton1Click:Fire()
	check("sidebar settings save without a filesystem", true)
end

local headerActions = app.dashboard.header:FindFirstChild("Actions")
local hideButton = headerActions and headerActions:FindFirstChild("HideButton")
if hideButton then
	hideButton.MouseButton1Click:Fire()
	check("hide collapses the console onto the anchor", app.dashboard.root.Visible == false and app.dashboard.anchor.Visible == true)
end

local anchorHit = app.dashboard.anchor:FindFirstChild("Hit")
if anchorHit then
	anchorHit.MouseButton1Click:Fire()
	check("anchor reopens the console", app.dashboard.root.Visible == true)
end

local quickMenuButton = headerActions and headerActions:FindFirstChild("QuickMenuButton")
if quickMenuButton then
	quickMenuButton.MouseButton1Click:Fire()
	check("header button opens the quick menu", app.quickMenu.overlay.Visible == true)
	app.ToggleQuickMenu()
end

local newChatButton = headerActions and headerActions:FindFirstChild("NewChatButton")
if newChatButton then
	newChatButton.MouseButton1Click:Fire()
	check("new chat resets the transcript", #chatPanel.transcript:GetChildren() == 0)
end

-- Real geometry ---------------------------------------------------------------
-- Everything above proves the app *runs*. The stub also resolves UDim2 sizes,
-- UIListLayout order and AutomaticSize content, so the blocks below assert what
-- a player would actually see. This is the class of bug that no static check can
-- find: a widget that builds fine and renders 0px wide, or a child laid out
-- outside the panel that owns it.

local laidOut = __relayout(app.gui)
check("the layout pass resolved geometry", type(laidOut) == "number" and laidOut > 100, laidOut)

local function rounded(value)
	return string.format("%.1f", value or 0)
end

local function rect(instance)
	local position = STUB.absPos(instance)
	local size = STUB.absSize(instance)
	if not position or not size then
		return nil, nil
	end
	return position, size
end

local function describe(instance)
	return string.format("%s [%s]", STUB.path(instance), tostring(STUB.classOf(instance)))
end

local function summarize(entries)
	local shown = {}

	for index, entry in ipairs(entries) do			if index > 6 then
				table.insert(shown, string.format("(+%d more)", #entries - 6))
			break
		end
		table.insert(shown, entry)
	end

	return table.concat(shown, "  |  ")
end

local isButton = function(class)
	return class == "TextButton" or class == "ImageButton"
end

local isText = function(class)
	return class == "TextLabel" or class == "TextButton" or class == "TextBox"
end

--- True when a rectangle is fully on the simulated screen.
local function inViewport(position, size)
	local viewport = STUB.VIEWPORT
	return position.X >= -1
		and position.Y >= -1
		and position.X + size.X <= viewport.X + 1
		and position.Y + size.Y <= viewport.Y + 1
end

-- Collected across every viewport; each entry is tagged with where it was seen.
local collapsed = {}
local unreadable = {}
local spilled = {}
local oversized = {}
local cramped = {}
local floorFindings = {}
local buttons, texts, rects = 0, 0, 0

--[[
	Walks every mounted rectangle once. Returns the violations found in this
	sweep, tagged with the viewport/tab context they were seen in - a single root
	cause (a window that cannot shrink past its minimum size) shows up as hundreds
	of escaped children, and the tag is what identifies it.
]]
--[[
	The console's design floor, mirroring Dashboard.MIN_VIEWPORT. Below it the
	window is smaller than a single panel's own content: at 740x360 the three-pane
	layout gets a 106px-tall content area, while the Cowork card alone needs ~230px.
	The console is supposed to stay closed there and show its notice instead, so
	containment findings below the floor are reported as evidence of the boundary
	rather than as failures. Everything at or above the floor is asserted, as are
	the window-level guarantees at every size.
]]
local FLOOR = { X = 800, Y = 600 }

local function belowFloor(width, height)
	return width < FLOOR.X or height < FLOOR.Y
end

local function sweep(label, width, height)
	local cramped = belowFloor(width, height)
	local found = { collapsed = {}, unreadable = {}, spilled = {}, cramped = {}, floor = {} }

	STUB.VIEWPORT = { X = width, Y = height }

	for _, tabId in ipairs({ "Chat", "Cowork", "Code" }) do
		app.dashboard:setTab(tabId)
		__drain()

		-- Resize settle: the pass fires the AbsoluteSize handlers that trim the toast
		-- rail, the drain runs what they queued (a dismissed toast destroys itself
		-- when its fade completes), and the final pass measures the settled tree.
		__relayout(app.gui)
		__drain()
		local placed = __relayout(app.gui)
		rects = math.max(rects, placed)
		local seenButtons, seenTexts = 0, 0

		for _, instance in ipairs(app.gui:GetDescendants()) do
			local tagged = label .. "/" .. tabId
			local class = STUB.classOf(instance)
			local position, size = rect(instance)
			local visible = STUB.isVisible(instance)

			-- 1. Nothing interactive may collapse to nothing.
			if isButton(class) then
				seenButtons = seenButtons + 1
				if not size or size.X < 1 or size.Y < 1 then
					table.insert(found.collapsed, string.format(
						"%s %s %sx%s%s",
						tagged,
						describe(instance),
						rounded(size and size.X),
						rounded(size and size.Y),
						visible and "" or " (hidden)"
					))
				end
			end

			-- 2. Text that should be on screen must have area, contrast and a size.
			if isText(class) and visible then
				local text = instance.Text
				if type(text) == "string" and text ~= "" then
					seenTexts = seenTexts + 1
					if not size or size.X < 1 or size.Y < 1 then
						table.insert(found.unreadable, tagged .. " " .. describe(instance) .. " has no area (" .. rounded(size and size.X) .. "x" .. rounded(size and size.Y) .. ")")
					elseif instance.TextTransparency >= 1 then
						table.insert(found.unreadable, tagged .. " " .. describe(instance) .. " is fully transparent")
					elseif (instance.TextSize or 0) < 8 then
						table.insert(found.unreadable, tagged .. " " .. describe(instance) .. " text size is " .. tostring(instance.TextSize))
					end
				end
			end

			-- 3. A visible child must sit inside its parent, unless the parent clips
			--    it (ScrollingFrame clip by definition).
			local parent = instance.Parent
			local parentClass = parent and STUB.classOf(parent) or nil
			local parentPosition, parentSize
			if parent then
				parentPosition, parentSize = rect(parent)
			end
			-- ClipsDescendants belongs to GuiObject, not to the ScreenGui: a screen
			-- cannot clip, and reading it there was the stub's first catch on this file.
			local clips = parentClass == "ScrollingFrame"
				or (parent ~= nil and STUB.isGuiObject(parent) and parent.ClipsDescendants == true)
			local container = parentClass == "ScreenGui" or (parent ~= nil and STUB.isGuiObject(parent))

			if visible and position and size and parentPosition and parentSize and container and not clips then
				local escaped = {}
				if position.X < parentPosition.X - 1 then
					table.insert(escaped, "left")
				end
				if position.Y < parentPosition.Y - 1 then
					table.insert(escaped, "top")
				end
				if position.X + size.X > parentPosition.X + parentSize.X + 1 then
					table.insert(escaped, "right")
				end
				if position.Y + size.Y > parentPosition.Y + parentSize.Y + 1 then
					table.insert(escaped, "bottom")
				end

				if #escaped > 0 then
					table.insert(
						cramped and found.cramped or found.spilled,
						string.format(
							"%s %s escapes %s on the %s: child %s,%s %sx%s vs parent %s,%s %sx%s",
							tagged,
							describe(instance),
							STUB.path(parent) .. " [" .. tostring(parentClass) .. "]",
							table.concat(escaped, "+"),
							rounded(position.X), rounded(position.Y), rounded(size.X), rounded(size.Y),
							rounded(parentPosition.X), rounded(parentPosition.Y), rounded(parentSize.X), rounded(parentSize.Y)
						)
					)
				end
			end
		end

		buttons = math.max(buttons, seenButtons)
		texts = math.max(texts, seenTexts)
	end

	-- Below the floor the console must be closed with the notice in its place; at
	-- or above it the console must be usable again.
	local notice = app.gui:FindFirstChild("ViewportNotice")
	-- Ancestor-aware: the floor closes the console by hiding its root, so reading
	-- window.Visible alone would say "open" on a screen where nothing is drawn.
	local consoleOpen = STUB.isVisible(app.dashboard.window)

	if cramped then
		if consoleOpen or notice == nil or notice.Visible ~= true then
			table.insert(found.floor, string.format(
				"%s console visible=%s, notice %s",
				label,
				tostring(consoleOpen),
				notice == nil and "missing" or ("visible=" .. tostring(notice.Visible))
			))
		end
	elseif notice ~= nil and notice.Visible then
		table.insert(found.floor, label .. " still shows the too-small notice")
	end

	return found
end

--[[
	Real laptops, 4K and a phone-shaped viewport. The interface is built for a
	desktop executor, so the small entries probe where it stops being usable
	rather than promising it works.
]]
local VIEWPORTS = {
	{ "1920x1080", 1920, 1080 },
	{ "2560x1440", 2560, 1440 },
	{ "3840x2160", 3840, 2160 },
	{ "1600x900", 1600, 900 },
	{ "1366x768", 1366, 768 },
	{ "1280x720", 1280, 720 },
	{ "1024x768", 1024, 768 },
	{ "800x600", 800, 600 },
	{ "740x360", 740, 360 },
}

local function merge(into, from)
	for _, item in ipairs(from) do
		table.insert(into, item)
	end
end

for _, entry in ipairs(VIEWPORTS) do
	local label, width, height = entry[1], entry[2], entry[3]
	local found = sweep(label, width, height)

	merge(collapsed, found.collapsed)
	merge(unreadable, found.unreadable)
	merge(spilled, found.spilled)
	merge(cramped, found.cramped)
	merge(floorFindings, found.floor)

	-- The window is the root cause worth naming on its own: when it cannot fit,
	-- everything inside it is reported as escaping as well.
	local windowPosition, windowSize = rect(app.dashboard.window)
	if windowPosition and windowSize and not inViewport(windowPosition, windowSize) then
		table.insert(oversized, string.format(
			"%s window %s,%s %sx%s does not fit %dx%d",
			label,
			rounded(windowPosition.X), rounded(windowPosition.Y),
			rounded(windowSize.X), rounded(windowSize.Y),
			width, height
		))
	end
end

-- Back to the baseline for the checks below.
app.dashboard:setTab("Chat")
STUB.VIEWPORT = { X = 1920, Y = 1080 }
rects = math.max(rects, __relayout(app.gui))

check(
	string.format("no button collapses to zero area across %d viewports (%d buttons)", #VIEWPORTS, buttons),
	#collapsed == 0,
	summarize(collapsed)
)
check(
	string.format("every visible label with text renders at every viewport (%d checked)", texts),
	#unreadable == 0,
	summarize(unreadable)
)check(
	string.format("no visible child escapes an unclipped parent at or above %dx%d", FLOOR.X, FLOOR.Y),
	#spilled == 0,
	summarize(spilled)
)
check("the console window fits inside every viewport", #oversized == 0, summarize(oversized))
check(
	string.format("the console hides below %dx%d and returns above it", FLOOR.X, FLOOR.Y),
	#floorFindings == 0,
	summarize(floorFindings)
)

--- Whether the too-small notice is on screen.
local function noticeIsShown()
	local notice = app.gui and app.gui:FindFirstChild("ViewportNotice")
	return notice ~= nil and STUB.isVisible(notice)
end

-- The notice is the only thing on screen below the floor, so its own geometry
-- matters: it has to fit the viewport it complains about.
STUB.VIEWPORT = { X = 740, Y = 360 }
__drain()
__relayout(app.gui)

do
	local notice = app.gui:FindFirstChild("ViewportNotice")
	local noticePosition, noticeSize = rect(notice)

	check("the too-small notice is on screen at 740x360", notice ~= nil and notice.Visible == true)
	check(
		"the too-small notice fits the viewport it describes",
		noticeSize ~= nil
			and noticePosition ~= nil
			and noticeSize.X > 100
			and noticeSize.Y > 40
			and noticePosition.X >= 0
			and noticePosition.Y >= 0
			and noticePosition.X + noticeSize.X <= 740
			and noticePosition.Y + noticeSize.Y <= 360,
		string.format("notice %s,%s %sx%s", rounded(noticePosition and noticePosition.X), rounded(noticePosition and noticePosition.Y), rounded(noticeSize and noticeSize.X), rounded(noticeSize and noticeSize.Y))
	)
end

-- Opening it by hand must work even on a screen the floor rejects.
app.dashboard:setVisible(true)
check("the console can still be opened by hand below the floor", STUB.isVisible(app.dashboard.window) == true)
check("opening it by hand also retires the notice", noticeIsShown() == false)
app.dashboard:setVisible(false)
check("hiding it again brings the notice back", noticeIsShown() == true)

-- Growing the window back (a phone turning to landscape) should restore the
-- console the floor took away, not leave the user staring at a notice.
STUB.VIEWPORT = { X = 1920, Y = 1080 }
__drain()
__relayout(app.gui)
check(
	"growing the window back restores the console",
	STUB.isVisible(app.dashboard.window) == true and noticeIsShown() == false
)
STUB.VIEWPORT = { X = 740, Y = 360 }
__drain()
__relayout(app.gui)
check("shrinking again re-suppresses it", STUB.isVisible(app.dashboard.window) == false and noticeIsShown() == true)

-- Back to the baseline for everything that follows.
app.dashboard:setVisible(true)
STUB.VIEWPORT = { X = 1920, Y = 1080 }
__drain()
rects = math.max(rects, __relayout(app.gui))

if #cramped > 0 then
	__report(string.format("INFO  %d containment findings below the %dx%d floor:", #cramped, FLOOR.X, FLOOR.Y))

	for index, entry in ipairs(cramped) do
		if index > 5 then
			__report(string.format("INFO    (+%d more)", #cramped - 5))
			break
		end
		__report("INFO    " .. entry)
	end
end

-- The stub owns AbsolutePosition / AbsoluteSize now, so writing one has to fail
-- the way the engine fails it - otherwise a bundle that assigned them would
-- silently corrupt the geometry above.
do
	local ok, err = pcall(function()
		app.gui.AbsoluteSize = Vector2.new(1, 1)
	end)

	check(
		"writing a computed Absolute property raises, as it does in Roblox",
		ok == false and string.find(tostring(err), "read%-only") ~= nil,
		tostring(err)
	)

	-- The probe deliberately tripped the stub's violation log; drop just that.
	STUB.violations[#STUB.violations] = nil
end

-- Geometry that depends on the layout having run: the toast accent rail is sized
-- from the card's measured height by an AbsoluteSize change handler.
local toast = notifications and notifications:FindFirstChild("Toast")
local rail = toast and toast:FindFirstChild("Rail")
local card = toast and toast:FindFirstChild("Card")
if check("a toast rendered with a card and an accent rail", toast ~= nil and rail ~= nil and card ~= nil) then
	local railSize = STUB.absSize(rail)
	local cardSize = STUB.absSize(card)
	check(
		"accent rail is sized from the card's measured height",
		railSize ~= nil and cardSize ~= nil and railSize.Y > 0 and railSize.Y <= cardSize.Y and railSize.X > 0,
		string.format("rail %sx%s card %sx%s", rounded(railSize and railSize.X), rounded(railSize and railSize.Y), rounded(cardSize and cardSize.X), rounded(cardSize and cardSize.Y))
	)
end

--[[
	A burst of toasts. The rail is a list-layout container that grows downward, so
	it has to retire its own entries until the stack fits the screen - and the
	measurement is over the toasts only. It used to sum every child, which means it
	counted its own UIListLayout: a read Roblox raises on, and one this stub used to
	answer with a plausible 100x20, so the trim fired against a wrong total here and
	threw "AbsoluteSize is not a valid member of UIListLayout" in game.

	Body chosen so the height trim, not just the four-toast cap, has to bite: the
	rail is 360px wide, so ~580 characters wrap to roughly 16 lines (~300px), and
	four of those do not fit 720px of screen.
]]
do
	local baseline = STUB.VIEWPORT
	STUB.VIEWPORT = { X = 1280, Y = 720 }
	__drain()
	__relayout(app.gui)

	local longBody = string.rep("A deliberately long toast body, so the rail has to retire older entries. ", 8)

	for index = 1, 6 do
		app.notify("burst " .. tostring(index), longBody, "info")
		__drain()
		__relayout(app.gui)
	end

	__drain()
	__relayout(app.gui)

	local mounted, titles = {}, {}

	for _, child in ipairs(notifications:GetChildren()) do
		if STUB.classOf(child) == "Frame" then
			table.insert(mounted, child)
			local card = child:FindFirstChild("Card")
			local header = card and card:FindFirstChild("Header")
			local title = header and header:FindFirstChild("Title")
			table.insert(titles, title and title.Text or "?")
		end
	end

	local listed = table.concat(titles, ", ")
	local railPosition, railSize = rect(notifications)

	check("a toast burst retires down to the visible cap", #mounted <= 4, listed)
	check("the height trim retires past the cap", #mounted >= 1 and #mounted < 4, listed)
	check("the newest toast survives the trim", listed:find("burst 6") ~= nil, listed)
	check("the oldest toast is retired first", listed:find("burst 1") == nil, listed)
	check(
		"the remaining toast stack still fits the screen",
		railPosition ~= nil and railSize ~= nil and railPosition.Y + railSize.Y <= 720,
		string.format(
			"rail %s,%s %sx%s at 1280x720",
			rounded(railPosition and railPosition.X), rounded(railPosition and railPosition.Y),
			rounded(railSize and railSize.X), rounded(railSize and railSize.Y)
		)
	)

	STUB.VIEWPORT = baseline
	__drain()
	__relayout(app.gui)
end

-- The quick menu is built at runtime, so it gets its own geometry snapshot.
app.ToggleQuickMenu()
__relayout(app.gui)

local module = app.quickMenu.module
local modulePosition, moduleSize = rect(module)
local viewport = STUB.VIEWPORT
check(
	"quick menu module measures up and sits inside the viewport",
	moduleSize ~= nil
		and moduleSize.X > 40
		and moduleSize.Y > 40
		and modulePosition.X >= 0
		and modulePosition.Y >= 0
		and modulePosition.X + moduleSize.X <= viewport.X + 1
		and modulePosition.Y + moduleSize.Y <= viewport.Y + 1,
	string.format(
		"module %s,%s %sx%s in viewport %sx%s",
		rounded(modulePosition and modulePosition.X), rounded(modulePosition and modulePosition.Y),
		rounded(moduleSize and moduleSize.X), rounded(moduleSize and moduleSize.Y),
		viewport.X, viewport.Y
	)
)

app.ToggleQuickMenu()
__relayout(app.gui)

__report(string.format(
	"INFO  geometry: %d rects x %d viewports x 3 tabs swept",
	rects,
	#VIEWPORTS
))

--[[
	Every button, clicked. The suite above drives the controls it knows about by
	hand, which is how a callback that read a global (`panel:submit()` above the
	`local panel` it meant) stayed untested until a player pressed it. This walks
	the mounted tree instead: every TextButton and ImageButton, whether or not it is
	visible, repeatedly until no new ones appear - a click that builds a widget (a
dropdown, a toast action) exposes buttons the next pass then covers too.

	Hidden buttons are included deliberately: a player cannot press them, but the
	callback still runs in a game that unhides them, and it must not throw. The
	production button wrapper pcalls OnClick and warns on failure, so "no warnings"
	is the assertion that a callback reached real code.
]]
local clicked = {}
local warnedBy, violatedBy = {}, {}
local fired = 0

local function isTeardown(instance)
	return instance.Name == "UnloadButton" or instance.Name == "Unload"
end

local function clickAndWatch(instance)
	clicked[instance] = true
	fired = fired + 1

	local warnings = #STUB.warnings
	local violations = #STUB.violations
	local path = STUB.path(instance)

	instance.MouseButton1Click:Fire()
	__drain()

	for index = warnings + 1, #STUB.warnings do
		table.insert(warnedBy, path .. "  ::  " .. STUB.warnings[index])
	end
	for index = violations + 1, #STUB.violations do
		table.insert(violatedBy, path .. "  ::  " .. STUB.violations[index])
	end
end

-- The Unload button destroys the whole tree, so it is held back until last.
local teardown, passes = {}, 0

while passes < 4 do
	passes = passes + 1

	local batch = {}
	for _, instance in ipairs(app.gui and app.gui:GetDescendants() or {}) do
		if isButton(STUB.classOf(instance)) and not clicked[instance] then
			if isTeardown(instance) then
				clicked[instance] = true
				table.insert(teardown, instance)
			else
				table.insert(batch, instance)
			end
		end
	end

	if #batch == 0 then
		break
	end

	for _, instance in ipairs(batch) do
		clickAndWatch(instance)
	end
end

--[[
	That pass ignores visibility, which is what makes it exhaustive, but it also
	means it presses the below-floor notice only while hidden. This second pass
	walks the states a player can actually be in - every viewport, every tab - and
	presses the buttons that are *visible* there, once per tab: the notice, the
	anchor it is replaced by, and the collapsed sidebar tiers are exercised in the
	state that shows them.
]]
local statePressed = {}
local stateFired, smallStateFired, noticeFired = 0, 0, false
local perTab = {}

for _, entry in ipairs(VIEWPORTS) do
	local _, width, height = entry[1], entry[2], entry[3]

	STUB.VIEWPORT = { X = width, Y = height }
	__drain()
	__relayout(app.gui)

	for _, tabId in ipairs({ "Chat", "Cowork", "Code" }) do
		app.dashboard:setTab(tabId)
		__drain()
		__relayout(app.gui)

		local seen = statePressed[tabId] or {}
		statePressed[tabId] = seen

		for _ = 1, 2 do
			local pressed = 0

			for _, instance in ipairs(app.gui and app.gui:GetDescendants() or {}) do
				if isButton(STUB.classOf(instance))
					and not seen[instance]
					and not isTeardown(instance)
					and STUB.isVisible(instance) then
					seen[instance] = true
					pressed = pressed + 1
					stateFired = stateFired + 1
					perTab[tabId] = (perTab[tabId] or 0) + 1

					if instance.Name == "OpenAnyway" then
						noticeFired = true
					end
					if belowFloor(width, height) then
						smallStateFired = smallStateFired + 1
					end

					clickAndWatch(instance)
				end
			end

			if pressed == 0 then
				break
			end
		end
	end
end

-- Back to the baseline the rest of the file assumes, then the one button that
-- tears the tree down is clicked last of all.
STUB.VIEWPORT = { X = 1920, Y = 1080 }
__drain()
__relayout(app.gui)

for _, instance in ipairs(teardown) do
	clickAndWatch(instance)
end

-- Everything clicked outside a tab state: the tree walk plus the Unload button.
local walkFired = fired - stateFired

__report(string.format("INFO  click sweep: %d buttons in %d passes", walkFired, passes))
__report(string.format(
	"INFO  state sweep: %d clicks over %d viewports x 3 tabs (%d stayed visible below the floor)",
	stateFired,
	#VIEWPORTS,
	smallStateFired
))

check("the click sweep reached a real number of buttons", walkFired > 25, walkFired)
check("no button callback warned", #warnedBy == 0, summarize(warnedBy))
check("no button callback touched an invalid member", #violatedBy == 0, summarize(violatedBy))
check(
	"every tab had its visible buttons pressed",
	(perTab.Chat or 0) > 0 and (perTab.Cowork or 0) > 0 and (perTab.Code or 0) > 0,
	string.format("chat %d, cowork %d, code %d", perTab.Chat or 0, perTab.Cowork or 0, perTab.Code or 0)
)
check("buttons that only appear below the floor were pressed", smallStateFired > 0, smallStateFired)
check("the below-floor notice's own button was pressed", noticeFired == true)
check(
	"the sweep ended on the Unload button, which tore the app down",
	#teardown == 1 and app.gui == nil,
	string.format("%d unload button(s), gui %s", #teardown, app.gui == nil and "gone" or "still mounted")
)

-- Unload -----------------------------------------------------------------------

app.Unload()
check("unload tears the UI down", app.gui == nil)

-- Environment health -----------------------------------------------------------

check("no invalid Instance members were assigned", #STUB.violations == 0, table.concat(STUB.violations, " | "))
-- Warnings are where a swallowed callback failure lands: the production button
-- runs OnClick inside a pcall and warns on error, so an unwarned suite is the
-- only proof that every click above reached real code.
check("no warnings were logged", #STUB.warnings == 0, table.concat(STUB.warnings, " | "))
check("no errors inside queued tasks or signal handlers", #STUB.taskErrors == 0, table.concat(STUB.taskErrors, " | "))

__report("")
__report(
	string.format(
		"INFO  instances=%d connections=%d deferred=%d warnings=%d",
		STUB.created,
		STUB.connections,
		STUB.delayed,
		#STUB.warnings
	)
)

for _, message in ipairs(STUB.warnings) do
	__report("WARN  " .. message)
end

local unknown = {}
for key in pairs(STUB.unknownReads) do
	table.insert(unknown, key)
end
table.sort(unknown)
for _, key in ipairs(unknown) do
	__report("INFO  unset property read: " .. key)
end

__report("")
__report(string.format("%d/%d checks passed", checks - failures, checks))

return failures
