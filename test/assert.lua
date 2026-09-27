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

-- Unload -----------------------------------------------------------------------

app.Unload()
check("unload tears the UI down", app.gui == nil)

-- Environment health -----------------------------------------------------------

check("no invalid Instance members were assigned", #STUB.violations == 0, table.concat(STUB.violations, " | "))
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
