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
- [x] Right-to-erasure tooling: `scripts/erase-user.luau` (Open Cloud; run with `--dry-run`
      first, it has not been run against the live service). See MANUAL_STEPS.md §11.
- [x] Admin/support tools: `/inspect`, `/trade`, `/grant` chat commands (`AdminService`,
      allow-list in `config/Admin.luau`, audit-logged).
- [x] Cross-server announcements for Mythic hatches (`GlobalAnnounceService`, rate limited
      on both publish and receive).
- [x] Rejoin cooldown: cheer history is keyed by UserId and survives rejoining the same
      server (still per server; a server hop resets it).
- [x] Coin packs scale with the player's tier (`Rewards.tierCoinScale`); the shop shows
      the scaled amount.
- [x] Shop UI: affordability colours refresh in place on coin changes.
- [x] Profile size monitoring (warn at 1 MB, error at 3 MB; once per level per profile).

## Nice to have

- [ ] Play-test the new visuals (WorldDecor, AtmosphereController) in Studio; tune part count / Atmosphere density on mobile.
- [x] Hatch animation.
- [ ] Real critter models and habitat decorations (cosmetic coin sink): need art / a design
      decision on pricing.
- [ ] Friends/party: teleport to a friend's server, "visit ranch" button.
- [x] Gamepad navigation: bright selection ring (`SelectionImageObject`). Not tested with a
      real controller.
- [x] Trade history panel (last 20 trades are kept in the profile: `trades.history`).
