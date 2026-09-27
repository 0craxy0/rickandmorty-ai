\# PNG Asset and Image Usage Specification: Rick \& Morty AI Executor



This document details the configuration, file path placement, and behavioral framework for the specific image assets present in the project directory: `title.png`, `rick.png`, and `morty.png`.



\## 1. Local Directory Asset Mapping



Since this script utilizes an executor layout, images are loaded directly from the local workspace directory using standard file-path strings.



\* \*\*Main Logo Asset Path\*\*: `title.png`

\* \*\*Rick Portrait Asset Path\*\*: `rick.png`

\* \*\*Morty Portrait Asset Path\*\*: `morty.png`



\---



\## 2. Character Companion Configurations ("Little Buddies")



The `rick.png` and `morty.png` files serve as active companion sprites embedded within the main UI console frame.



\* \*\*Placement\*\*: Positioned inside an `ImageLabel` in the bottom-right corner of the active sidebar or chat canvas.

\* \*\*Sizing\*\*: Constrained to a crisp `64x64` pixel frame with `ScaleType = Enum.ScaleType.Fit`.

\* \*\*ZIndex\*\*: Configured to `ZIndex = 5` to hover neatly above standard dark message bubbles without overlapping structural text.

\* \*\*Dynamic Hover Effect\*\*: When hovered, a subtle UI script applies a neon scaling bump (`Size = UDim2.new(0, 70, 0, 70)`) using `TweenService`.



\---



\## 3. Onboarding Tutorial Guide Systems



When a user initializes the system for the first time, they must pick an AI companion. The chosen headshot morphs into the structural tutorial anchor.



\### Tutorial Frame Elements

\* \*\*The Guide Avatar\*\*: The selected character headshot (`rick.png` or `morty.png`) scales up to `128x128` pixels on the side of the overlay window.

\* \*\*The Structural Pointer\*\*: Since external assets are limited, a custom vector arrow is drawn natively using a rotated square frame or a native Roblox UI asset, attaching directly to the side of the headshot frame.

\* \*\*Pointer Animation\*\*: A continuous code loop updates the pointer's pixel offset using a sine-wave calculation (`math.sin(tick() \* 5) \* 10`) to bounce next to the UI button being explained.



\---



\## 4. Main Menu Title Integration



The core branding relies entirely on the title image asset to establish the sci-fi theme immediately upon menu execution.



\* \*\*Main Window Header\*\*: `title.png` is anchored at the top-center of the large main console window.

\* \*\*Quick Menu Header\*\*: Scaled down to 50% width and centered inside the temporary semicolon overlay menu frame.

\* \*\*Sizing Ratio\*\*: Maintained via `UIAspectRatioConstraint` to ensure the title graphics do not warp, stretch, or pixelate across differing screen resolutions.



