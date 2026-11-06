# TODO

Every known gap is listed here (the code contains no inline TODO markers).

## Must do before public launch

- [ ] **Play-test in Studio** following the checklist in `MANUAL_STEPS.md` (section 9). The
      server/client code has been compiled, linted, unit-tested and smoke-tested outside
      Roblox, but never executed inside the engine.
- [ ] Create passes/products in Creator Hub and fill `src/shared/config/Monetization.luau`.
- [ ] Complete the Maturity & Compliance questionnaire (Content rating).
- [ ] Replace placeholder audio/icons at minimum (`ASSETS_TO_REPLACE.md`).
- [ ] Set max players per server to 6 (world has 6 plots).
- [ ] Type-check with `luau-lsp analyze` (could not be run in the build environment; the
      code is written with `--!strict` but has not been verified by the type checker).

## Should do soon

- [ ] Background music: the player is wired (SoundController) and follows the `music` setting; upload a track and set `Assets.sounds.music`.
- [ ] Localization: UI strings are inline English; move to LocalizationService tables.
- [ ] Right-to-erasure tooling: a script that removes `u_<userId>` from `PlayerData_v1`,
      `pending_<userId>` from `TradeJournal_v1`, and the user's entries in the leaderboard
      stores (see MANUAL_STEPS.md §11).
- [ ] Admin/support tools: inspect a profile, view a trade record by id, grant compensation.
- [ ] Cross-server announcements for Mythic hatches (MessagingService), rate limited.
- [ ] Rejoin cooldown: the in-memory cheer hourly cap resets on rejoin (minor exploit).
- [ ] Coin packs could scale with progression (currently fixed amounts).
- [ ] Shop UI: refresh affordability colours on coin changes without rebuilding lists.
- [ ] Profile size monitoring (warn when JSON size > 1 MB; hard limit is 4 MB).

## Nice to have

- [ ] Play-test the new visuals (WorldDecor, AtmosphereController) in Studio; tune part count / Atmosphere density on mobile.
- [ ] Real critter models, hatch animation, habitat decorations (cosmetic coin sink).
- [ ] Friends/party: teleport to a friend's server, "visit ranch" button.
- [ ] Gamepad navigation polish (buttons are Activated-based, so they work, but there is no
      selection highlight).
- [ ] Trade history panel (records already exist in `TradeJournal_v1`).
