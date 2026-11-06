# Skyheart Ranch

A cooperative creature-ranch collection simulator for Roblox. Players hatch elemental
critters from nests on floating sky ranches, chase rare mutations, keep critters in
habitats for passive income, trade safely, and fill the server-wide **Skyheart** together
to trigger a **Bloom** that buffs everyone.

* Design: [`DESIGN.md`](DESIGN.md) (loop, 25+ species, rarities, mutations, economy,
  co-op, trading, monetization, data schema, assumptions)
* What you must do by hand (Studio, Creator Hub, publishing): [`MANUAL_STEPS.md`](MANUAL_STEPS.md)
* Placeholder art/audio to replace: [`ASSETS_TO_REPLACE.md`](ASSETS_TO_REPLACE.md)
* Known gaps: [`TODO.md`](TODO.md)

## Features

| Area | What's in |
|---|---|
| Farm loop | Nest shop (5 tiers + reward/tutorial nests), plant/grow/hatch with server timers and offline progress, habitats with passive income (offline 50 %, 8 h cap), selling, locking, upgrades |
| RNG | Weighted rarity → species → mutations (groups, cap 3, combos) → size; luck multiplier; pity guarantees; one function computes both the roll and the displayed odds |
| Co-op | Skyheart goal that scales with player count and progression (works solo), Bloom buff + reward nests, weather events, Cheer neighbours' nests, community coin bonus |
| Trading | Requests, trade window, versioned offers, ready → 5 s lock → confirm, reservations, coin spend guard, journal-based atomic commit with roll-forward on load, trade log |
| Retention | Server-owned tutorial (~3 min), non-punishing 7-day daily reward, daily/weekly quests with reroll, index with milestones, global leaderboards, config-driven seasonal events |
| Monetization | 4 passes, 7 products, idempotent ProcessReceipt, odds disclosure + luck boost before/after, PolicyService gating (paid random items, paid item trading) |
| UI | Mobile-first, single UIScale, safe insets, large touch targets, toasts, celebrations, announcements, tutorial arrows/highlights |
| Safety | Session-locked saves with lost-lock detection, migrations, autosave, BindToClose, guarded + rate-limited remotes, analytics wrapper, pcall around every external service |

## Tech

* Luau (`--!strict` in all game modules), Rojo 7 project, Rokit toolchain
  (Rojo, StyLua, Selene, Lune, Wally)
* No runtime dependencies. TestEZ is a dev dependency for running specs inside Studio.
* Tests run outside Roblox with Lune through a TestEZ-compatible runner.

## Getting started

```bash
rokit install                 # tools from rokit.toml
rojo plugin install           # Studio plugin (once)
rojo serve                    # then Plugins → Rojo → Connect in Studio
```
Full walkthrough (creating the experience, API access, products, publishing):
[`MANUAL_STEPS.md`](MANUAL_STEPS.md).

### Checks

```bash
lune run tests/lune/run.luau     # compile-check every file + unit tests (105)
lune run tests/lune/smoke.luau   # builds world, critter visuals and every UI panel (71 checks)
lune run tests/lune/audit.luau   # network audit: guards, rate limits, handlers, directions
stylua --check src tests
selene src tests/specs
rojo build -o build/game.rbxl
```
Inside Studio: `wally install`, `rojo serve test.project.json`, press Play.

## Project structure

```
src/
  shared/                         → ReplicatedStorage.Shared
    config/      all balance numbers and IDs (Creatures, Nests, Mutations, Economy,
                 Upgrades, Coop, Weather, Seasons, Quests, DailyRewards, Index,
                 Tutorial, Monetization, Trade, Data, World, Assets, …)
    logic/       pure, tested rules: HatchOdds, Hatchery, MutationRoller, Valuation,
                 GrowthMath, ModifierMath, Progression, CoopMath, QuestLogic
    net/         Remotes.luau (every remote, guards, rate limits) + Net.luau
    util/        Guard, RateLimiter, Signal, TableUtil, TimeUtil, Format, ObjectPool
    Types.luau
  server/                         → ServerScriptService.Server
    init.server.luau   bootstrap (Init → Start → PlayerReady → full Sync)
    data/        SessionStore, DataStoreAdapter, MockDataStore, Migrations,
                 ProfileTemplate, ReceiptLogic
    trade/       TradeRules, TradeJournal, TradeSession (pure / injectable)
    services/    DataService, SyncService, Analytics, PolicyCache, PassService,
                 ModifierService, EconomyService, InventoryService, RewardService,
                 WorldService, PlotService, FarmService, MarketService,
                 UpgradeService, IndexService, WeatherService, SkyheartService,
                 CheerService, TradeService, QuestService, DailyRewardService,
                 SettingsService, TutorialService, LeaderboardService,
                 MonetizationService
    ServerEvents.luau, Notifier.luau, CreatureVisuals.luau
  client/                         → StarterPlayerScripts.Client
    init.client.luau, ClientState.luau (read-only mirror of server state)
    ui/          Theme, UI kit, CreatureCard
    controllers/ UI, Sound, Notification, Hud, WorldFx, Farm, Shop, Inventory,
                 Index, Quest, Trade, Tutorial, Event, Leaderboard
tests/
  specs/         TestEZ specs (SessionStore, Migrations, Hatch, Economy, Balance,
                 Coop, Trade, Quests, Receipts, Util)
  lune/          run.luau, smoke.luau, audit.luau, loader.luau, testez.luau
  studio/        RunTests.server.luau (Studio TestEZ bootstrap)
```

## Architecture notes

**Server authority.** Clients only send intents through remotes declared in
`net/Remotes.luau`. Before any handler runs, `Net` checks that the profile is loaded,
applies a per-player token bucket, validates every argument (type, range, format, array
shape, no extra args) and wraps the handler in `pcall`. Repeated malformed payloads kick
the player. Handlers then validate game rules (ownership, limits, unlocks, distance for
Cheer). The client never computes money, odds outcomes, items or trade results.

**Data safety.** `SessionStore` locks each profile with `UpdateAsync` and a heartbeat;
saves re-check ownership so a stale server can never overwrite newer data. A failed load
never creates a fresh profile, and future-schema data is never overwritten. Purchases are
granted at most once per `PurchaseId` and acknowledged only after a successful save.
Trades use a commit journal so they are applied fully or not at all, even across crashes.

**Performance.** No per-frame server work: growth runs on a 1 s tick, income every 5 s,
sync is batched (~6/s) with creature deltas. The placeholder world stays under ~450 parts
with 6 full ranches; eggs and critter models are pooled; StreamingEnabled is on and the
client never assumes world parts are present.

**Analytics.** Onboarding funnel (tutorial steps), economy sources/sinks with transaction
types (income aggregated per minute), progression (nest tier unlocks), custom events
(hatches by rarity, mutations, trades, quests, daily, purchases, Bloom rewards). Server
script errors are counted via ScriptContext.

## Verification status

Done here: compile check of every file, 105 unit tests (including statistical roll tests,
balance checks and a crash matrix for trades), a smoke test that builds the world, every
critter visual and every UI panel against Roblox's reflection data, a static network
audit, StyLua and Selene (full Roblox std) clean, `rojo build` succeeds.

**Not yet verified:** running inside Roblox (physics, prompts, teleport, real DataStores,
purchases, mobile layout on devices) and static type checking with luau-lsp. Follow the
checklist in `MANUAL_STEPS.md` §9.

## Roadmap — first 4 weeks after release

**Week 1 — Stabilise & tune.** Watch Analytics daily: tutorial funnel drop-off per step,
D1 retention, economy sources vs sinks, purchase conversion. Fix any errors from the
Developer Console. Tune nest prices/grow times and Skyheart targets from real data (all in
config). Replace placeholder audio and icons. Ship small hotfixes 2–3 times this week.

**Week 2 — First content drop.** Add a 6th nest tier ("Aurora Nest"), 3–4 new species and
one new mutation + combo (config + visuals). Expand quest pools. Add habitat decorations as
a cosmetic coin sink. Add friend invites (`SocialService:PromptGameInvite`) and a "visit
ranch" teleport for friends.

**Week 3 — Harvest Festival (already scheduled in `config/Seasons.luau`, Nov 20 – Dec 4
2026).** Event species Gourdling, Harvest mutation, +10 % coins. Add event-only quests and
an event leaderboard; announce in-game and in the experience description. Track event
participation and spend.

**Week 4 — Deeper co-op & social.** Multi-stage Skyheart (bigger goals unlock stronger
Blooms), neighbour gifts, trade history panel, weekly leaderboard with cosmetic rewards.
Review monetization with the price-optimisation tools in Creator Hub (no new pay-to-win
items). Prepare Winter Frost (Dec 18 – Jan 8, already in config).
