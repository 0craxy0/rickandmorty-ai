\# Backend \& Architecture Specification: Rick \& Morty AI Executor



This document details the backend logic, network handling, filesystem operations, and system-prompt mechanics required to power the Rick \& Morty AI UI system.



\## 1. Persona Prompt Injection Engine



The backend must intercept every new conversation chain to inject the thematic character profiles before sending the payload to the selected API provider. This must happen seamlessly without displaying the raw system prompt text inside the user's visible chat UI log.



```lua

\-- Backend prompt structure framework

local PersonaPrompts = {

&#x20;   Rick = "Act like Rick from the famous show 'Rick and Morty' when explaining, debugging, writing or editing code. Be cynical, highly intelligent, slightly erratic, use his iconic speech patterns, and dismissive yet helpful.",

&#x20;   Morty = "Act like Morty from the famous show 'Rick and Morty' when explaining, debugging, writing or editing code. Be anxious, stutter slightly, hesitant, but trying your absolute best to help out."

}



function PreparePayload(userChoice, userPrompt, providerTemplate, chatHistory)

&#x20;   local systemMessage = PersonaPrompts\[userChoice]

&#x20;   local fullMessages = {}

&#x20;   

&#x20;   -- Inject system persona rule at the start of a fresh chain

&#x20;   if #chatHistory == 0 then

&#x20;       table.insert(fullMessages, { role = "system", content = systemMessage })

&#x20;   end

&#x20;   

&#x20;   -- Append historical logs

&#x20;   for \_, msg in ipairs(chatHistory) do

&#x20;       table.insert(fullMessages, msg)

&#x20;   end

&#x20;   

&#x20;   -- Append the immediate active prompt

&#x20;   table.insert(fullMessages, { role = "user", content = userPrompt })

&#x20;   

&#x20;   -- Merge into the structural API template

&#x20;   local finalPayload = HttpService:JSONDecode(providerTemplate)

&#x20;   finalPayload.messages = fullMessages

&#x20;   

&#x20;   return HttpService:JSONEncode(finalPayload)

end

```



\---



\## 2. Cowork Mode Filesystem Bridge



When the user switches to \*\*Cowork Mode\*\*, the script uses the executor's native filesystem functions to build the local file bridge directly inside the host machine's workspace folder.



\### Step-by-Step Execution Sequence

1\. \*\*Directory Generation\*\*: Check for or generate a `/rick\_morty\_bridge/` subdirectory within the executor workspace.

2\. \*\*File Creation\*\*: Write out `launch\_bridge.bat` (Windows) or `launch\_bridge.sh` (Mac/Linux) natively using `writefile()`.

3\. \*\*Payload Structure\*\*: The written batch file contains standard terminal commands to pull, install, or launch the external high-fidelity node environment targeting `http://localhost:7896`.

4\. \*\*User Verification\*\*: Trigger a customized notification window with `rick.png` or `morty.png` pointing to instructions telling the user to double-click the newly generated bridge file inside their executor's folder directory.



\---



\## 3. Network Request Handler \& Proxy Routes



Because the Roblox engine blocks direct client-side external requests to specific third-party domain endpoints (like `://openai.com`), all outgoing data passes through proxy setups or the executor's privileged HTTP hook requests.



\### Key Networking Architectures

\* \*\*Privileged Execution\*\*: Use `syn.request`, `http.request`, or `request` based on the host exploit suite to bypass standard Roblox engine `HttpService:PostAsync` domain whitelisting restrictions.

\* \*\*Header Configurations\*\*: Custom injection blocks dynamically append the user's private authorization bearer tokens (`Authorization: Bearer YOUR\_KEY`) and content configurations (`Content-Type: application/json`) safely into the secure requests.



\---



\## 4. Semicolon Quick-Menu Injection Logic



The compact fast-generation menu operates via a localized, fast-response loop designed to write code directly into the workspace without spinning up heavy interface tasks.



\* \*\*Key Handling\*\*: Binds via `UserInputService.InputBegan` to detect the semicolon key `;`. 

\* \*\*Input Interception\*\*: Immediately sinks user keyboard focus to prevent character movement or unintended in-game chat opening.

\* \*\*Hot-loading Code\*\*: Upon submitting the prompt, the backend sends a rapid stream chunk back from the selected provider, isolates the raw code block via string manipulation patterns (````lua ... ````), and targets it directly into a standard script container instance inside the local `Workspace`.



