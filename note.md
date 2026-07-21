# Tactical Weapon Motion — Design Notes

**Status (July 2026):** The **universal addon** (`Inventory_WeaponTilter.zs`) adopts the *techniques* below — baseline+absolute pendulum dip, roll integrator/smoothing, billboard roll→X, drift detection. **Optional** PB/Brutal-family compat (`wt_pb_compat`: Off / Auto / On) adds overlay sync, extra idle labels, scoped/token safety, and expanded weapon lists when Project Brutality, Brutal Pack, Brutal Doom, or Schism is detected. For a **PB-native** build with full PBWP menus and lean, use **PBWP** (`PB_WeaponTacticalFeel_Inventory.zc`).

Notes from the **Project Brutality Weapons Pack (PBWP)** integration pass (Dithered Output / agent-assisted). These describe how smooth **strafe rotational tilt** and **pendulum weapon lowering** were achieved on complex addon weapons, and how those techniques relate to this universal tilter fork.

**PBWP reference implementation:** `PB_WeaponTilterInventory` in PBWP (`zscript/Weapons/PB_WeaponTacticalFeel_Inventory.zc`).

**This mod’s implementation:** `WeaponTilterInventory` in `ZSCRIPT/Inventory_WeaponTilter.zs` + `WeaponTilterEventHandler.WorldTick()` for pose application.

---

## Goals

1. **Strafe tilt** — weapon rolls toward the strafe direction while moving sideways, with inertia and smoothing (not instant snapping).
2. **Pendulum lowering** — while tilted and strafing, the weapon **drops slightly** so long barrels / wide sprites stay below the screen edge instead of clipping the top.
3. **Stability** — no jitter, no runaway Y drift, no carry-over onto weapon switches or scoped ADS.
4. **Compatibility** — work across hundreds of weapons with different ready-state names, overlay layers, and per-tic pose rewrites.

---

## Architecture

### PBWP approach (single pass)

An undroppable inventory item runs **`DoEffect()` every tic** and writes directly to `PSP_WEAPON`:

- `psp.Rotation = displayRoll`
- `psp.Y = baselineWeaponY + smoothedPendulumDip` (absolute, not cumulative)

An `EventHandler` only **gives** the inventory on `PlayerEntered` and handles lean keybind console events.

### Universal mod approach (compute + apply split)

This fork computes `outputRoll` / `outputLowerY` in **`DoEffect()`**, then applies them in **`WorldTick()`** via `ApplyPose()`:

```zsc
ClearAppliedPose(psp);   // undo last tic’s delta
psp.Rotation += outputRoll;
psp.Y += outputLowerY;
```

Both patterns work. The critical difference for lowering is **how Y is tracked**, not whether apply happens in `DoEffect` or `WorldTick`.

---

## Smooth rotational tilt

### Strafe signal

Project player velocity onto the **strafe axis** (perpendicular to view angle):

```zsc
Vector2 strafeDir = (sin(-owner.angle), cos(-owner.angle));
double strafeDot = (owner.Vel.X * strafeDir.X) + (owner.Vel.Y * strafeDir.Y);
```

Positive `strafeDot` ≈ strafe right; negative ≈ strafe left. This is smoother than raw `cmd.sidemove` because it follows actual movement (including momentum and friction).

### Roll integrator (momentum + damping)

Each tic while motion is allowed:

```zsc
currentRoll += strafeDot * cvRollVelocity * motionEnableBlend;
currentRoll *= cvRollResistance;   // PBWP default ~0.15 — strong decay, “weighted” feel
```

Optional hard cap:

```zsc
if (cvCapRoll)
    currentRoll = clamp(currentRoll, -cvRollCap, cvRollCap);
```

### Direction-change dampening

When strafe direction flips, bleed off energy instead of fighting the previous roll:

```zsc
if (prevStrafeDot * strafeDot < 0. && abs(strafeDot) > 0.02 && abs(prevStrafeDot) > 0.02)
    currentRoll *= 0.55;
prevStrafeDot = strafeDot;
```

This removes the “whip crack” when tapping A/D or reversing mid-strafe.

### Display smoothing (exponential filter)

Raw `currentRoll` is noisy. PBWP smooths before applying:

```zsc
double tiltS = clamp(cvTiltSmoothing, 0.5, 0.95);   // PBWP default 0.70
smoothedWeaponRoll = smoothedWeaponRoll * tiltS + currentRoll * (1.0 - tiltS);
double displayRoll = smoothedWeaponRoll + leanRoll;  // leanRoll is optional Q/E offset
```

Higher `tiltS` = smoother/slower response. **0.65–0.75** is a good range for PB-style weapons.

### Motion enable blend (soft gate)

Instead of instantly enabling/disabling tilt when entering ready state or starting movement, PBWP ramps a **0→1 blend factor**:

```zsc
if (allowMotion)
    motionEnableBlend += (1.0 - motionEnableBlend) * 0.15;
else
    motionEnableBlend += (0.0 - motionEnableBlend) * 0.15;
```

Roll accumulation is multiplied by `motionEnableBlend`, so tilt **fades in/out** rather than popping.

When blocked entirely, roll also decays: `currentRoll *= 0.75`.

### Optional lean overlay (PBWP only)

Separate from strafe physics — inventory tokens `PB_LeanLeft`, `PB_LeanRight`, `PB_LeanToggle` drive a **target lean angle** that lerps into `leanRoll` and adds to `displayRoll`. This is weapon-only roll; camera lean in this universal mod is handled by the Immerse Lean block in the same file.

### Overlay sync (PB-heavy weapons)

Many PB weapons attach extra sprites on overlay layers. PBWP mirrors roll to:

**Layers 10, 11, 60, 61, 63, 64**

If addon weapons look “broken in half” while tilting, extend the same loop for your mod’s overlay indices.

---

## Pendulum lowering — the main fix

### The bug (accumulation)

Early attempts used **delta accumulation**:

```zsc
psp.Y += dip;   // every tic, never fully undone
```

Many weapon ready loops **do not reset `psp.Y` every frame**. Adding dip each tic made the weapon **sink off-screen** within seconds. Undoing with `psp.Y -= lastDip` also failed when weapon states **rewrote Y every tic** (the subtract targeted the wrong baseline).

### The solution (baseline + absolute Y)

Track the weapon’s **authored baseline Y** separately from the dip offset:

```zsc
// State
double baselineWeaponY;
double lastAppliedDip;
double smoothedPendulumDip;
bool hasBaselineWeaponY;

void ApplyPendulumDip(PSprite psp, double dip)
{
    // Drift detection: weapon state changed Y underneath us
    if (hasBaselineWeaponY && lastAppliedDip > 0.05)
    {
        double expectedY = baselineWeaponY + lastAppliedDip;
        if (abs(psp.Y - expectedY) > 2.0)
        {
            baselineWeaponY = psp.Y;   // re-sync to new authored pose
            lastAppliedDip = 0;
        }
    }
    else if (!hasBaselineWeaponY)
    {
        baselineWeaponY = psp.Y - lastAppliedDip;
        hasBaselineWeaponY = true;
    }

    if (dip > 0.05)
    {
        psp.Y = baselineWeaponY + dip;   // ABSOLUTE — never +=
        lastAppliedDip = dip;
    }
    else
    {
        psp.Y = baselineWeaponY;
        lastAppliedDip = 0;
    }
}
```

**Why this is smooth:** dip target is separately smoothed (`smoothedPendulumDip`), then written as an absolute offset from a stable baseline. When the weapon anim resets Y, drift detection re-captures baseline instead of fighting it.

### Dip target formula (asymmetric pendulum)

Lowering only applies when:

- Tilt/lowering is allowed (ready, not scoped, not blocked)
- `|displayRoll| > 0.1`
- Player is strafing (`|cmd.sidemove| >= 64` **or** `|strafeDot| > 0.15`)

```zsc
double scale = max(0.5, cvLoweringScale);   // PBWP default 0.65
double dip = (4.0 + absRoll * 6.0) * scale;

// Left strafe (negative roll) dips more — keeps muzzle below top edge
if (displayRoll < 0)
    dip += absRoll * 6.0 * scale;
else
    dip += absRoll * 1.2 * scale;

dip = min(dip, 18.0);   // hard cap in pixels
```

Asymmetric weighting matches player expectation: **left-strafe + CCW roll** lifts the muzzle toward the screen top on wide sprites, so it needs more counter-dip.

### Dip smoothing (attack / release)

```zsc
double dipRate = dipTarget > smoothedPendulumDip ? 0.22 : 0.16;   // faster rise, slower fall
smoothedPendulumDip += (dipTarget - smoothedPendulumDip) * dipRate;
if (smoothedPendulumDip <= 0.05)
    smoothedPendulumDip = 0;
```

Slightly faster attack than release avoids lag when starting a strafe but prevents the weapon from bouncing when stopping.

### Restore on block / switch

When lowering must stop (scoped, kick, weapon change, deselect):

```zsc
void RestorePendulumDip(PSprite psp)
{
    if (psp && hasBaselineWeaponY)
        psp.Y = baselineWeaponY;
    // clear dip state
}
```

On **weapon class change**, clear roll/dip **without** restore if switching away (deselect anim owns Y). On **pending weapon change** (deselect in progress), restore dip so raise anim starts clean.

---

## Roll-only mode (anti-jitter)

Some weapons **reset `psp.Y` (and sometimes rotation) every tic** in their ready loop — often layered ZScript/DECORATE weapons (Cyberaugumented base, Stormcast, Thunder Crossbow, Legendary Plasmatic Rifle).

For these, **Y lowering causes visible jitter** (baseline and authored Y fight each frame). PBWP sets **roll-only**:

```zsc
bool rollOnly = (weap is "PBWP_CA_WeaponBase")
    || weaponClass == 'Stormcast'
    || weaponClass == 'ThunderCrossbow'
    || weaponClass == 'LegendaryPlasmaticRifle';

if (rollOnly) {
    psp.Rotation = displayRoll;
    RestorePendulumDip(psp);
    return;
}
```

**Rule of thumb:** if a weapon “vibrates” vertically with lowering enabled, add it to a roll-only list before tuning dip.

---

## State gating (when motion is allowed)

### Ready-state allowlist

PB weapons use dozens of ready label names. PBWP checks a **broad allowlist** instead of only `Ready` / `Hold`:

`SelectContinue`, `SelectAnimation`, `Ready3`, `Ready_ADS`, `IdleNoAmmo`, `NoBuzzing`, `ReadySettle`, `ReadyToFire`, etc.

Fallback: if the weapon has **no** `RealReady` state, plain `Ready` counts.

### Ready vs motion-allowed

**Motion-allowed** includes select-animation states (weapon visible, settling). **Ready-only** (optional CVar) excludes `SelectContinue` / `SelectAnimation` so tilt waits until idle.

### Safety blocks

Motion is suppressed when:

| Condition | Reason |
|-----------|--------|
| Scoped ADS (`Zoomed`, `ADSMode`, or in `ZoomIn`/`ZoomFire`/`ScopedFire`/`Fire_ADS`) | ADS must stay aligned |
| Overlays 10/11 active outside ready | Melee/equipment anims |
| Fatality / execution tokens | Full-screen scripted anims |
| Kick / equipment / grenade tokens | Competing pose systems |
| Weapon in exclusion list | Minigun, BFG, etc. |

### Scoped weapon list

Maintain a **per-mod class list** for weapons that zoom. PBWP example: `PB_Railgun`, `PBX_BattleRifle`, `Gauss`, `HeavySniperRifle`, etc.

---

## CVars (PBWP defaults)

| CVar | Default | Role |
|------|---------|------|
| `pb_tac_enable` | true | Master toggle |
| `pb_tac_roll_velocity` | 2.0 | Strafe → roll gain |
| `pb_tac_roll_resistance` | 0.149687 | Per-tic damping |
| `pb_tac_roll_cap` / `pb_tac_roll_cap_value` | true / 3.0 | Max roll |
| `pb_tac_tilt_smoothing` | 0.70 | Display roll filter |
| `pb_tac_lowering_scale` | 0.65 | Pendulum dip intensity |
| `pb_tac_ready_only` | false | Restrict to idle ready |
| `pb_tac_move_only` | false | Require movement |
| `pb_tac_lean_enable` | true | Q/E weapon lean overlay |

Universal mod equivalents: `wt_rollvelocity`, `wt_rollresistance`, `wt_rollcap`, `wt_lowering_intensity`, `wt_tilt_ready`, `wt_tilt_moving`, etc.

---

## Porting checklist (Universal mod ← PBWP lessons)

If updating `Inventory_WeaponTilter.zs` with PBWP-style stability:

- [ ] **Replace or hybridize Y lowering** — consider baseline+absolute dip instead of (or in addition to) `+= outputLowerY` delta in `ApplyPose`, especially for weapons that rewrite Y each tic.
- [ ] **Add drift detection** — when `|psp.Y - (baseline + dip)| > 2`, re-sync baseline.
- [ ] **Expand ready-state allowlist** — PB addon weapons rarely use bare `Ready` alone.
- [ ] **Add roll-only class list** for jittery layered weapons.
- [ ] **Asymmetric dip** — stronger lowering when `displayRoll < 0` if top-edge clipping persists.
- [ ] **Direction-change roll dampening** (`currentRoll *= 0.55` on strafe sign flip).
- [ ] **Exponential roll smoothing** with tunable `tilt_smoothing` CVar.
- [ ] **motionEnableBlend** soft gate on allow/disallow transitions.
- [ ] **Clear pose on weapon switch / PendingWeapon** — never carry dip into raise anim.
- [ ] **Scoped state detection** — tokens + zoom fire state labels, not just `ZoomIn`.
- [ ] **Mirror rotation to overlay layers** if your target gameplay mod uses them.

---

## Debugging tips

1. **Weapon sinks over time** → accumulation bug; switch to baseline+absolute Y.
2. **Weapon vibrates while idle strafing** → roll-only list or authored Y conflict; disable dip for that class.
3. **No tilt until long after ready** → state not in allowlist (e.g. `Ready3`, `SelectAnimation`).
4. **Tilt during ADS** → scoped gating incomplete; check tokens and fire-state labels.
5. **Tilt pops on start/stop** → lower `motionEnableBlend` ramp or increase `tilt_smoothing`.
6. **Left strafe clips top of screen** → raise left-strafe dip multiplier or `lowering_scale`.

---

## File map

| Project | Primary files |
|---------|----------------|
| **PBWP** | `zscript/Weapons/PB_WeaponTacticalFeel_Inventory.zc`, `PB_WeaponTacticalFeel.zc`, `CVARINFO` (`pb_tac_*`) |
| **Universal (this repo)** | `ZSCRIPT/Inventory_WeaponTilter.zs`, `ZSCRIPT/EventHandler_WeaponTilter.zs`, `CVARINFO.txt`, `MENUDEF.txt` |

---

*Written July 2026 from PBWP tactical-feel integration work. Adapt values and class lists to your target gameplay mod.*
