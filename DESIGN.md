# Skyheart Ranch — Design Document

> Working title. A cooperative creature-ranch collection simulator for Roblox.
> All balance numbers live in `src/shared/config/*`. Numbers quoted here are the
> launch defaults and are illustrative; **the config files are the source of truth.**

## 1. Pitch and positioning

Floating sky islands drift around a giant crystal called the **Skyheart**. Players
run small ranches on these islands: they plant **Nests**, hatch cute elemental
**Critters**, keep them in **Habitats** for passive income, sell or trade them, and
— together with everyone on the server — feed **Essence** to the Skyheart. When the
Skyheart is full it **Blooms**: the whole server gets a buff and every contributor
gets a reward nest.

How we differ from Grow a Garden / Fish It:

| Axis | Them | Skyheart Ranch |
|---|---|---|
| Fantasy | plants / fishing | collectible critters with personalities, elemental mutations |
| Social | mostly parallel solo play | shared server goal (Skyheart), "Cheer" neighbours' nests, server-wide Bloom buff that anyone can trigger |
| Fairness | heavy RNG | transparent odds everywhere, pity counters, free path to every rarity |
| Low CCU | buffs need many players | goal size scales with player count and progression, works with 1 player |

## 2. Core loop

```
 buy Nest (coins) ──► plant on Nest Bed ──► grows (server timer, offline too)
        ▲                                         │
        │                                         ▼
   coins ◄── sell ◄── Critter (rarity + mutations + size) ──► Habitat (passive coins)
        │                 │            │
        │                 │            └──► Trade with other players
        │                 └──► Index (collection rewards)
        └── upgrades (slots, growth speed, luck, backpack)

 every hatch / donation / cheer ──► Essence ──► Skyheart (server goal) ──► Bloom buff + reward nests
```

Session targets: first critter < 60 s, first sale < 2 min, first purchased nest < 3 min,
first Bloom on a solo server ≈ 10–12 min.

## 3. Critters

25 base species + seasonal event species. Each species has a fixed rarity, base value,
colour and placeholder body shape (see `config/Creatures.luau`).

| Rarity | Species |
|---|---|
| Common (6) | Puffpaw, Mossnib, Bubbloo, Pebblit, Dandeleap, Snoozel |
| Uncommon (5) | Glimmoth, Thornback, Splashfin, Cindertail, Breezeling |
| Rare (5) | Frostwhisk, Voltkit, Lumashroom, Coralyn, Duskowl |
| Epic (4) | Crystalhorn, Stormwing, Emberdrake, Tidalpup |
| Legendary (3) | Aurorabbit, Solmane, Gloomwyrm |
| Mythic (2) | Nimbuswhale, Starweaver |
| Event | Gourdling (Epic, Harvest Festival), Frostfawn (Legendary, Winter Frost) |

Every critter instance stores: unique GUID `id`, `species`, `rarity`, `mutations[]`,
`size` (0.80–1.25), `obtainedAt`, `source` (hatch/trade/reward/tutorial), `locked` flag.

### 3.1 Rarities

| Rarity | Value band | Essence on hatch | Server announce |
|---|---|---|---|
| Common | 18–30 | 1 | – |
| Uncommon | 80–110 | 2 | – |
| Rare | 380–520 | 6 | – |
| Epic | 2.4k–3.4k | 20 | – |
| Legendary | 16k–24k | 80 | yes |
| Mythic | 140k–220k | 400 | yes |

### 3.2 Nests (where randomness happens)

Rolling a hatch: **rarity** (weighted by the nest table, modified by luck and pity) →
**species** (uniform within rarity, event species added while a season is active) →
**mutations** → **size**.

| Nest | Cost | Grow | Unlock (total hatched) | C / U / R / E / L / M (%) |
|---|---|---|---|---|
| Meadow | 60 | 30 s | 0 | 70 / 25 / 4.5 / 0.5 / – / – |
| Grove | 280 | 90 s | 5 | 40 / 38 / 17 / 4.5 / 0.5 / – |
| Crystal | 1,600 | 4 min | 25 | – / 40 / 37 / 19 / 3.7 / 0.3 |
| Storm | 6,500 | 10 min | 75 | – / – / 40 / 42 / 16 / 2 |
| Celestial | 19,000 | 20 min | 200 | – / – / – / 52 / 40 / 8 |
| Skyheart (reward only) | – | 150 s | – | – / 40 / 40 / 17 / 2.7 / 0.3 |

A unit test (`Balance.spec`) asserts each purchasable nest has expected value ≥ 1.25×
cost and that profit per minute per slot grows with tier.

### 3.3 Luck and pity (fully disclosed)

* **Luck multiplier** `L ≥ 1` multiplies the weight of every rarity flagged
  `luckAffected` (Rare and above), then the table is renormalised. Sources: Luck
  upgrade (+5 %/level, coins), Luck Boost product (×2 for 15 min), events. Capped at ×3.
* **Pity**: counters of hatches since the last Rare+/Epic+/Legendary+. At 15 / 75 / 400
  the next hatch is restricted to that tier or better (only tiers the nest can roll).
* The odds panel shows the **player's real current odds** — computed by the *same*
  function the server uses to roll — including luck, events and pity status.

### 3.4 Mutations

Each mutation rolls independently, then exclusivity groups and a max count (3) are
resolved by keeping the highest multipliers.

| Mutation | Base chance | Value × | Group | Visual placeholder |
|---|---|---|---|---|
| Shiny | 4 % | 1.5 | – | Sparkles |
| Giant | 2 % | 2 | size | scale ×1.8 |
| Tiny | 2 % | 1.3 | size | scale ×0.6 |
| Frozen | 1 % | 2.5 | – | Ice material, cyan |
| Electric | 1 % | 2.5 | – | yellow PointLight |
| Golden | 0.5 % | 4 | metal | gold Foil |
| Shadow | 0.25 % | 5 | – | dark Highlight |
| Rainbow | 0.15 % | 8 | metal | colour cycle (client) |
| Cosmic | 0.05 % | 12 | – | star particles |
| Harvest (event) | 0 % (2 % in Harvest Festival) | 3 | – | orange tint |

**Combos** (extra multiplier when both present): Frozen+Electric = *Thunderfrost* ×1.5,
Shadow+Cosmic = *Voidborn* ×2, Golden+Shiny = *Gilded* ×1.25, Rainbow+Giant =
*Prismatic Titan* ×1.5.

Chance modifiers multiply per mutation: weather events (e.g. Blizzard Frozen ×6),
Skyheart Bloom (all ×1.5), seasonal events. Final chance is capped at 50 %.

### 3.5 Value

```
value     = species.baseValue × Π(mutation.mult) × Π(combo.mult) × size
sellPrice = floor(value × passMultiplier × (1 + bloomBonus + communityBonus + seasonBonus))
```
`value` is the intrinsic number shown everywhere (inventory, trade window).
`sellPrice` adds temporary/personal multipliers and is shown on the Sell button.

## 4. Economy

**Sources:** selling critters, habitat income (value / 1800 per second; offline at 50 %,
capped at 8 h), quests, daily rewards, index milestones, cheering, Bloom rewards,
coin packs (Robux).

**Sinks:** nests (main sink, scales with tier), upgrades (exponential), donating critters
to the Skyheart (item sink), trade tax on coins (5 %, burned).

**Item sinks / inflation control:** critters are removed on sell and donation; inventory
has a hard cap (400) and an upgradeable backpack (50 base).

Starting coins: 100. Upgrade tracks (`config/Upgrades.luau`): Nest slots 3→8,
Habitat slots 2→8, Growth speed +10 %/lvl ×5, Luck +5 %/lvl ×5, Backpack 50→175.

## 5. Co-op

* **Skyheart goal** — server-wide Essence meter. Target = Σ per-player share where the
  share grows with each player's highest unlocked nest tier (min 60). Recomputed on
  join/leave; progress never decreases, if target drops below progress the Bloom fires.
* **Bloom** (8 min): +50 % coins, ×1.25 growth, ×1.5 mutation chances for everyone
  on the server, including players who join during it. Every contributor receives a
  Skyheart Nest; the top contributor (if ≥ 2 contributors) gets one extra.
* **Essence sources:** hatching (by rarity), donating critters (3× rarity essence ×
  (1 + mutations)), cheering (1).
* **Cheer** — visit a neighbour's plot, tap a growing nest: +4 % progress, max 5 distinct
  cheerers per nest, 40 cheers/hour per helper. Helper gets coins + essence.
* **Community bonus** — +5 % coins per other player on the server (max +20 %).
* **Weather events** every 10–16 min (Blizzard, Thunderstorm, Golden Hour, Eclipse,
  Aurora, Meteor Shower, Growth Rain), 30 s warning, 3–4 min duration, announced in UI.
* **Robustness:** all co-op state is server-memory only, keyed by `userId`; leaving players
  are removed from the target but keep their personal rewards; nothing waits on a
  specific player.

## 6. Trading

1. Player A sends request → B accepts within 30 s (rate limits: 10 s per target, 6/min).
2. Shared trade window: up to 8 critters + coins per side; each item shows its value.
3. Any change to an offer resets both **Ready** flags.
4. Both Ready → 5 s **lock countdown** (offers frozen, either side may cancel).
5. Both press **Confirm** → server executes.

**Atomic execution (journal commit):**
1. Validate both offers against live profiles (ownership, not locked, not in habitat,
   capacity, balances, trade-unlock requirement, PolicyService trading flag).
2. Write a pending marker for each user (`pending_<userId>` → tradeId).
3. Write the trade record `trade_<id>` with status `committed` — **single-key commit point**.
4. Apply both halves in memory (pure `TradeRules.apply`), record the tradeId in each
   profile's `appliedTrades`, save both profiles.
5. Clean pending markers (best effort).

On profile load the server reads `pending_<userId>`; for each tradeId whose record is
committed but not in `appliedTrades` it **rolls forward** that user's half (idempotent).
Markers without a committed record are discarded (trade never happened). An ambiguous
commit error triggers a re-read; if still unknown both players are saved and kicked so
the next load resolves the truth. Result: a trade is either fully applied for both
players or for neither, even across crashes. Records double as the trade log.

Restrictions: trading unlocks after 10 hatches; disabled for players whose policy has
`IsPaidItemTradingAllowed = false`; a player can be in one trade at a time; items in a
trade cannot be sold/donated/placed.

## 7. Retention and onboarding

* **Tutorial (≈3 min, icon-driven):** free Starter Nest (10 s) → hatch a guaranteed Shiny
  Puffpaw (celebration) → place in Habitat (coins start ticking) → first reward chest
  (+100) → buy a Meadow Nest → done (+150). Arrows, highlight rings and a beam guide each
  step; the server owns step state and rewards.
* **Daily reward:** 7-day cycle, **non-punishing** (missing a day never resets progress).
* **Quests:** 3 daily (one free reroll/day) and 3 weekly; rewards scale with progression
  tier so they stay relevant. Co-op quests only in weekly (works on small servers).
* **Index:** species and species×mutation discoveries; milestone rewards.
* **Leaderboards:** global (OrderedDataStore) for coins earned and index entries;
  in-server `leaderstats`.
* **Seasonal events:** `config/Seasons.luau` entries with UTC start/end, modifiers,
  extra species, extra mutation chances. Adding an event = adding a table entry.

## 8. Monetization (honest by design)

| Type | Item | Effect |
|---|---|---|
| Game pass | Double Coins | ×2 sell price and habitat income |
| Game pass | Extra Nest Slots | +2 nest slots (max 10) |
| Game pass | Big Backpack | +100 backpack capacity |
| Game pass | VIP | cosmetic: gold nameplate tag, VIP plot trim, chat-style tag |
| Product | Luck Boost (15 min) | luck ×2 — before/after odds shown before purchase |
| Product | Growth Boost (15 min) | growth ×2 |
| Product | Instant Grow | finishes all growing nests now |
| Product | Server Bloom | triggers Skyheart Bloom for the whole server |
| Product | Coin packs S/M/L | fixed coin amounts |

Rules we follow:
* No critter or nest is sold directly for Robux. Nests bought with coins are still
  treated as paid random items (coins can be bought), so **odds are always displayed**
  before buying, as percentages, with a rounding disclaimer and a descriptive button.
* Luck boosts are numerically explained and the odds view updates live while active.
* `PolicyService.ArePaidRandomItemsRestricted` → coin packs, Luck Boost and Server Bloom
  are hidden and blocked server-side for that player.
* `IsPaidItemTradingAllowed = false` → trading disabled for that player.
* No timers that punish, no fake discounts, no pop-up ads, no loss-aversion streaks.
* Free path: pity guarantees + Skyheart Nests + daily rewards make every rarity
  reachable without spending; passes only speed things up.

## 9. Data schema (profile v1)

Stored in DataStore `PlayerData_v1`, key `u_<userId>`, wrapped as
`{ data = Profile, meta = { sessionId, lockedAt, heartbeat, saveCount } }`.

```
Profile = {
  schemaVersion: number,
  coins: number,
  creatures: { [id]: Creature },            -- inventory
  inventoryNests: { [nestId]: count },
  nests: { [slot "1".."10"]: { nestId, progress, required, lastUpdate, cheers = {[uid]=true} } },
  habitats: { [slot "1".."8"]: creatureId },
  upgrades: { nestSlots, habitatSlots, growthSpeed, luck, backpack },
  index: { species = { [speciesId] = { at, mutations = { [m] = true } } }, claimed = { [milestoneId] = true } },
  pity: { rarePlus, epicPlus, legendaryPlus },
  boosts: { luckUntil, growthUntil },
  income: { lastAccrual, carry },
  daily: { lastClaimDay, cycleDay },
  quests: { dayKey, daily = {...}, rerollsUsed, weekKey, weekly = {...} },
  tutorial: { step, done },
  purchases: { receipts = { [purchaseId] = ts }, passes = { [passKey] = true } },
  trades: { applied = { [tradeId] = ts } },
  stats: { coinsEarned, hatched, sold, donated, cheersGiven, trades, playSeconds, firstJoin, lastJoin, sessions },
  settings: { sfx, music },
}
```

* **Migrations:** ordered list `fromVersion → fn(data)` in `server/data/Migrations.luau`,
  applied on load until `schemaVersion == CURRENT`; then `reconcile` deep-fills missing
  fields from the template (additive changes need no migration).
* **Session locking:** custom `SessionStore` on `UpdateAsync`; heartbeat every autosave;
  a lock is stealable only when its heartbeat is older than 5 min; every save verifies
  the lock is still ours, otherwise the profile is marked lost and the player is kicked
  (prevents stale-server overwrites).
* **Saves:** autosave 60 s, on leave, on `BindToClose` (parallel, 25 s budget), after
  purchases and trades; retries with exponential backoff; budget-aware.
* Critter IDs are GUIDs from `HttpService:GenerateGUID(false)`; trade and receipts are
  idempotent by id.

## 10. Architecture

```
src/shared   ReplicatedStorage.Shared   config/, logic/ (pure, tested), util/, net/
src/server   ServerScriptService.Server services/, data/, trade/
src/client   StarterPlayerScripts.Client controllers/, ui/
```
* Server **services** and client **controllers** follow `Init()` then `Start()`.
* `net/Net.luau` declares every remote once (name, kind, argument guards, rate limit);
  the server wrapper validates types, ranges, and frequency before any handler runs.
* The client is a view: it renders replicated state and sends *intents*.

## 11. Assumptions (decisions made without asking)

1. Working title "Skyheart Ranch"; setting is floating sky islands with elemental critters.
2. 6 players per server (6 plots). Recommended max players in Creator Hub: 6.
3. Custom session-locked store instead of ProfileStore: no external dependency, fully
   unit-testable with a mock DataStore, and the trade journal integrates with it.
4. One soft currency (Coins). Essence is server-level, not a wallet.
5. UI text in English with strings in one module for later localisation.
6. Tests run outside Roblox with Lune via a TestEZ-compatible runner; the same specs
   can run in Studio with TestEZ (`test.project.json`).
7. Coin packs are fixed amounts (no scaling) for transparency.
8. Trade tax 5 % on coins only (inflation sink, discourages RMT); critters untaxed.
9. Habitat income auto-credits while online; offline income shown in a "Welcome back" popup.
10. Daily streak never resets (child-friendly).
