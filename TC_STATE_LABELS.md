# TC Weapon State Labels — Survey & Universal Strategy

Survey source: archived TCs under  
`Ultimate Doom\(Doom Mod Builds)\.TCs` (Brutal Pack, Bloom, Clusterfuck, Ashes, D4V, Callsign:Zero, etc.).

**Goal:** stay universal by default — PB/Brutal extras are **opt-in** via `wt_pb_compat`. Use **allowlist + engine fallback**, not “block everything unknown.”

---

## Optional PB / Brutal family compat (`wt_pb_compat`)

| Mode | Behavior |
|------|----------|
| **Off** | Universal only — no overlay layers, no PB inventory token checks |
| **Auto** (default) | Enables compat when loaded mod defines known marker classes (`SwitchableWeapon`, `BrutalMapEnhancer`, `PB_Minigun`, `BDPBattleRifle`, `GoFatality`, …) |
| **On** | Force compat even if auto-detect misses (custom merges) |

When active: overlay roll on PSprite layers **10, 11, 60, 61, 63, 64**; PB idle labels (`Ready_ADS`, `BDReady3`, …); scoped gating via `Zoomed`/`ADSMode`; safety blocks for fatalities/kicks/grenades; expanded `NO_ROTATE` / `ROLL_ONLY` / `SCOPED` lists.

Schism is Brutal Doom–based — auto-detect picks it up via shared BD/PB marker classes.

---

## Recommended universal approach (implemented)

| Layer | What it does |
|-------|----------------|
| **1. Core idle allowlist** | `Ready`, `Hold`, `ReadyLoop`, `Idle`, `GunReady`, `WaitReady` — matches vanilla + most TCs |
| **2. Extended idle allowlist** | Common BD/TC variants (`Ready2`, `RealReady`, `ReadyToFire`, `SelectAnimation`, …) |
| **3. Engine fallback** | `wf_weaponready` when **not** in combat or switch states — covers custom labels we don't list |
| **4. Combat blocklist** | Explicit `Fire`, `Reload`, `Melee`, … — never tilt during these |
| **5. `wf_weaponbobbing`** | Additional motion gate (classic universal tilter behavior) |

**Why not match any label containing `Ready`?**  
Many animation states use `Ready` as a prefix but are **not** idle (e.g. `ReadyLamp`, `ReadyBarrel`, `ReadyImpFatality`). Allowlist-only avoids false positives.

**`wt_tilt_ready` ON:** strict mode — **core allowlist only** (no extended labels, no engine fallback).

---

## Idle label frequency (top hits, 30 major archives)

| Label | Approx. hits | Notes |
|-------|-------------|--------|
| `Ready` | 3700+ | Universal default |
| `Idle` | 846 | Common in modern TCs |
| `ReadyLoop` | 828 | Standard ready loop |
| `Ready2` | 330 | BD family |
| `Ready3` | 228 | BD family |
| `Hold` | 72 | Alternate idle |
| `ReadyToFire` | 54 | Pre-fire idle |
| `RealReady` | 47 | BD “true” ready |
| `SelectAnimation` | 46 | Raise/settle — motion OK, optional strict exclude |
| `ReallyReady` | 13 | BD variant |

Labels **not** added (not idle): `ReadyLamp`, `ReadyBarrel`, `ReadyImpFatality`, `Ready*Fatality*`, etc.

---

## Combat label frequency (blocklist)

| Label | Approx. hits |
|-------|-------------|
| `Melee` | 641 |
| `Fire` | 457 |
| `Reload` | 301 |
| `ReloadLoop` | 144 |
| `AltFire` | 140 |
| `Fire2` | 102 |

Extended blocklist in code includes `Fire2/3`, `Melee2`, `ReloadLoop2`, `ChargeLoop`, etc.

---

## Porting into a specific TC

1. **Try the addon as-is first** — engine fallback handles many unknown ready labels.
2. If tilt never starts: add that mod's idle label to `extendedIdle[]` in `Inventory_WeaponTilter.zs`.
3. If tilt runs during the wrong anim: add the label to `combatLabels[]`.
4. If Y jitters on one weapon: add class to `ROLL_ONLY[]`.
5. For **PB / Brutal Pack / Brutal Doom / Schism**, set **`wt_pb_compat`** to Auto or On — or use **PBWP** for the full PB-native menu/lean stack.

---

## Code locations

| Array / function | File |
|------------------|------|
| `coreIdle[]`, `extendedIdle[]` | `IsCoreIdleState`, `IsExtendedIdleState` |
| `combatLabels[]` | `IsCombatWeaponState` |
| `wf_weaponready` fallback | `IsWeaponIdleForTilt` |
| Strict ready option | CVAR `wt_tilt_ready` |
| PB/Brutal compat | CVAR `wt_pb_compat`, `ProbeBDFamily()`, `IsPbExtendedIdleState`, overlay layers |

*Survey run July 2026. Re-run against `.TCs` when adding labels for a new target mod.*
