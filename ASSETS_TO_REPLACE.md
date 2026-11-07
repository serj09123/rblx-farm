# Placeholder assets to replace

Everything visual and audible in the current build is a placeholder made from
primitive parts, emoji and one built-in sound. Replace these before (or soon after)
launch. Code locations are listed so swapping is mechanical.

## Audio — `src/shared/config/Assets.luau` → `sounds`

| Key | Used for | Current | Replace with |
|---|---|---|---|
| click | every button | `rbxasset://sounds/electronicpingshort.wav` (built-in) | soft UI tap |
| coins | rewards, sales | built-in ping | coin jingle |
| hatch | common hatch | built-in ping | egg crack + pop |
| rare | rare/mutated hatch, announcements | built-in ping | sparkle sting |
| mythic | Legendary/Mythic hatch | built-in ping | big fanfare |
| bloom | Skyheart Bloom | built-in ping | magical swell |
| trade | trade request/complete | built-in ping | handshake chime |
| error | errors | silent | short muted buzz |
| music | background music (not wired yet, see TODO.md) | silent | calm looping track |

Ready-made original replacements (synthesized by `scripts/make-audio.py`, royalty-free) are in
`assets/audio/*.wav`, one file per key above. Re-run the script to regenerate or tweak them.
They were not auditioned by ear when generated: listen before uploading.

Upload from the command line (Open Cloud; MP3 copies of the files are in `assets/audio/`):

```bash
ROBLOX_API_KEY=... lune run scripts/upload-audio -- --user <yourUserId> --dry-run   # check first
ROBLOX_API_KEY=... lune run scripts/upload-audio -- --user <yourUserId>
```
The key needs `asset:read` + `asset:write`. The script writes the resulting ids into
`Assets.luau` itself (use `--group <id>` for a group-owned experience). Roblox moderates
audio, so a sound may be silent in game until it is approved.

Or upload by hand: audio you own or have licensed (Creator Hub → Creations → Development Items → Audio),
then paste `rbxassetid://<id>`.

## Icons — `src/shared/config/Assets.luau` → `icons`

All HUD/panel icons are emoji glyphs (🪙 ✨ 🥚 🐣 🏡 🎁 🛒 🎒 📖 📜 🤝 📅 ⬆️ ⚡ 🍀 ✖ 💰 🔒 📣 💗 🌦️ ⚙️ 🎲 👑).
Replace with ImageLabels using uploaded decals for a consistent art style
(`src/client/ui/UI.luau` → `iconButton`, `src/client/ui/CreatureCard.luau`).

## Critters — `src/server/CreatureVisuals.luau`

Each critter is a coloured primitive (Ball/Block/Cylinder from `config/Creatures.luau`),
two eye spheres and a crest block. Replace with real models:

1. Model each species (25 + event species) as a Model with a PrimaryPart.
2. Put them in `ReplicatedStorage/Assets/Critters/<speciesId>` (add to the Rojo tree as `.rbxm`).
3. In `CreatureVisuals.build`, clone the model instead of building primitives; keep the
   mutation effects (they are applied to the body part / model).
4. Portraits in UI (`CreatureCard`) are coloured circles — replace with ViewportFrames or
   rendered thumbnails.

Mutation effects to polish: Shiny sparkles, Golden foil, Frozen ice, Electric light +
particles, Shadow Highlight (note: max 31 visible Highlights per client), Rainbow hue cycle
(client), Cosmic particles, Giant/Tiny scale, Harvest tint.

## Nests / eggs — `CreatureVisuals.egg`

A 3-stud sphere tinted with the nest colour; neon + particles when ready. Replace with egg
models per nest tier and a hatch animation.

## World — `src/server/services/WorldService.luau`

Flat grass ground, a plaza disc, three stalls (Nests, Sell, Upgrades), the Skyheart (neon
sphere on a pedestal), two leaderboard boards and six square plots with beds and pads.
Replace with a built map (floating islands theme). Keep these contracts:

* plot models need `PlotIndex` + `OwnerUserId` attributes,
* beds/pads need `Slot`, `Kind` ("Bed"/"Pad") attributes and a child `ProximityPrompt`
  with an `Action` attribute ("Bed"/"Pad"),
* hub prompts use `Action` = "Shop" / "Market" / "Upgrades" / "Skyheart",
* leaderboard parts need a `Board` attribute ("coins"/"index").

## Store and marketing

* Game icon (512×512) and at least 3 thumbnails (1920×1080).
* Icons for each game pass and developer product (512×512, important content inside the circle).
* Optional: promo video.
