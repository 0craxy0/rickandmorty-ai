\# UI Creation and Layout Specification: Rick \& Morty AI Executor



This document details the layout hierarchy, screen states, interactive components, and operational modes for the Rick \& Morty themed Roblox AI UI system.



\## 1. Core Interface Modes



The system operates via two distinct UI display states triggered by user input.



\### The Semicolon Quick-Menu

\* \*\*Trigger\*\*: Pressing the semicolon key `;` on the keyboard.

\* \*\*Background Effect\*\*: Spawns a full-screen semi-transparent black frame (`BackgroundColor3 = #0D1117`, `BackgroundTransparency = 0.4`) to darken the game world.

\* \*\*Layout\*\*: A compact, centered floating module featuring the scaled `title.png`, a single text input field, and a companion mini-avatar (`rick.png` or `morty.png`).

\* \*\*Behavior\*\*: Submitting text instantly sends the prompt to the selected AI provider, generating code directly into the workspace without opening the full application suite. Pressing escape or finishing execution closes the overlay and restores the game.



\### The Full-Sized Main Menu

\* \*\*Trigger\*\*: Executing the main command or clicking the expanded UI icon.

\* \*\*Background Effect\*\*: Zero background dimming; remains transparent over the game viewport.

\* \*\*Layout\*\*: A wide multi-panel dashboard containing a left sidebar for chat history and provider selection, a central workspace view, and an active companion frame in the bottom-right corner.

\* \*\*Navigation Tabs\*\*: Features clear switching between \*\*Chat\*\* (in-game AI prompt generation), \*\*Cowork\*\* (external local browser bridge), and \*\*Code\*\* (native in-UI code executor).



\---



\## 2. AI Providers and Preset API Templates



The settings panel allows users to configure and toggle between multiple API providers, each populated with a default request structure template.



| Provider Name | Endpoint / Connection Type | Default Payload Template |

| :--- | :--- | :--- |

| \*\*OpenRouter\*\* | `https://openrouter.ai` | `{"model": "anthropic/claude-3.5-sonnet", "messages": \[]}` |

| \*\*AgentRouter\*\* | Custom Local/Remote Gateway | `{"agent": "default", "prompt": ""}` |

| \*\*Anthropic\*\* | `https://anthropic.com` | `{"model": "claude-3-5-sonnet-20241022", "max\_tokens": 1024}` |

| \*\*OpenAI\*\* | `https://openai.com` | `{"model": "gpt-4o", "messages": \[]}` |

| \*\*DeepSeek\*\* | `https://deepseek.com` | `{"model": "deepseek-chat", "messages": \[]}` |

| \*\*FreeBuff\*\* | Local/Free Proxy Route | `{"provider": "freebuff", "input": ""}` |



\---



\## 3. Specialized Chatting Modes



The full-sized menu organizes interaction styles into three operational sub-systems:



\* \*\*Chat Mode\*\*: Standard conversational UI for prompting the AI to write, debug, or modify Luau code directly inside the game environment.

\* \*\*Cowork Mode\*\*: Initiates a local workspace bridge. The script downloads bridge batch files into the executor workspace. When the user opens the batch file, it launches `http://localhost:7896` presenting a high-fidelity, Claude-like external interface.

\* \*\*Code Mode\*\*: A built-in code editor and execution environment contained directly within the central UI pane, allowing direct script testing, line numbering, and syntax-highlighted output viewing.



\---



\## 4. Rick and Morty Persona Injection



To maintain strict thematic consistency, every initial prompt sent in a fresh conversation automatically prefixes a system-level directive based on user configuration.



\* \*\*Rick Selection\*\*: Automatically injects: `"Act like Rick from the famous show Rick and Morty when explaining, debugging, writing or editing code."`

\* \*\*Morty Selection\*\*: Automatically injects: `"Act like Morty from the famous show Rick and Morty when explaining, debugging, writing or editing code."`



\---



\## 5. Onboarding Tutorial and Companion Pointers



Upon first-time execution, users choose either `rick.png` or `morty.png` as their primary guide.



\* \*\*Guide Positioning\*\*: The selected portrait docks beside the tutorial text box at an enlarged scale.

\* \*\*Dynamic Pointer\*\*: A custom-drawn directional arrow graphic renders directly adjacent to the companion image, linked via a sine-wave oscillation loop to point precisely at active interface buttons (such as the provider dropdown or execution tab).

\* \*\*Text Rendering\*\*: Instructional dialogue types out character-by-character using the typewriter configuration (`0.03s` delay) alongside the single click-sound asset per letter.



