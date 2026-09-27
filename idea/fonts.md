\# Fonts and Typography Specification: Rick \& Morty AI Executor



This document outlines the font hierarchy, text rendering behaviors, and typographic audio assets for the Rick \& Morty themed Roblox AI UI system.



\## 1. Core Fonts (Roblox Font Enum)



To match the chaotic, sci-fi, and high-tech energy of the show, the UI utilizes two contrasting font types: \*\*Cartoony/Sci-Fi\*\* for headings/system messages, and \*\*Monospace\*\* for code editing/AI responses.



| UI Element | Roblox Font Enum | Visual Style Description |

| :--- | :--- | :--- |

| \*\*Main Headers \& Titles\*\* | `Enum.Font.LuckiestGuy` | Bold, bubbly, cartoon-style to mimic the iconic show logo styling. |

| \*\*Subheadings \& Buttons\*\* | `Enum.Font.GothamBold` | Clean, modern sci-fi geometry for interactive elements. |

| \*\*Body Text / Dialogue\*\* | `Enum.Font.Gotham` | Highly readable sans-serif for standard AI chats and tooltips. |

| \*\*Code Executor \& Editor\*\* | `Enum.Font.RobotoMono` | Crisp, uniform monospace font for code display, debugging, and terminal logs. |



\---



\## 2. Text Sizing and Scaling



Text elements must maintain specific scales to balance readability with a crowded, high-tech instrument look.



\* \*\*Main Interface Titles\*\*: 32pt, Bold, centered alignment.

\* \*\*Dialogue Text / Chat History\*\*: 14pt, Left alignment, wrapped.

\* \*\*Terminal/Code Output\*\*: 12pt, Left alignment, no clipping (enable scrolling).

\* \*\*Interactive Button Labels\*\*: 16pt, Bold, centered.



\---



\## 3. Letter-by-Letter Typewriter System



When Rick or Morty are speaking in the chat or acting as tutorial guides, text must render dynamically rather than instantly appearing.



\### Typewriter Mechanics

\* \*\*Speed\*\*: `0.03` seconds delay per character.

\* \*\*Skipping\*\*: Clicking anywhere on the active dialogue frame instantly displays the full text block.

\* \*\*RichText\*\*: `TextLabel.RichText` must be enabled to support markdown styling elements without breaking the character-by-character typewriter loop counters.



\### Typographic Audio FX

Every individual letter rendered by the typewriter system triggers a quick, sharp click sound to mimic sci-fi terminal interfaces.



\* \*\*Sound Asset ID\*\*: `rbxassetid://9114223164`

\* \*\*Properties\*\*: 

&#x20; \* `Volume`: `0.3`

&#x20; \* `PlaybackSpeed`: `1.2` (Slightly pitched up to keep it snappy and non-intrusive)



