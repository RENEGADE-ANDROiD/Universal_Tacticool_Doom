/*
Part of Universal Weapon Tilter by generic name guy.
You can download a copy of the source code or contribute to the project on GitHub at https://github.com/generic-name-guy/universal-weapon-tilt-gz/
This is code licensed under Unlicense, so do whatever you want with it, i don't care.
*/
// PLUS //
/////////////////////////////////////////////////////////
///// Strafing Weapon Tilt - with Wall Detection 	/////
///// 			For Project Brutaltiy				///// 
/////        	 by Dithered OutPut					///// 
/////////////////////////////////////////////////////////

/* ============================================================================
   Universal Weapon Tilter + Complete Leaning (Q/E + Strafe‑Lean Toggle)
   Camera roll for leaning, weapon tilt only from movement
   ============================================================================ */

class WeaponTilterInventory : Inventory
{
    // ------------------------------------------------------------
    // Weapon tilt variables
    double currentRoll, crABS, aVelocity, adjustedCrABS;
    float rResistance, rVelocity, rLimit, rWallLoweringAmount;
    vector2 direction, velocityUnit;
    int currentTickCount;
    bool limit, offset, lowering, wallDetection;
    double loweringAmount, loweringSmoothing;
    double duckAmount; // For wall detection lowering

    // ------------------------------------------------------------
    // Leaning variables
    bool last_strafelean;
    bool last_leanleft, last_leanright;
    double leantilt, leanlerp;
    int leandelay;
    double defaultattackzoffset;   // for weapon lowering during lean

    // ------------------------------------------------------------
    // Weapon exclusion arrays (example – adjust to your own weapons)
    static const string NO_ROTATE[] =
    {
        "PB_Minigun", "PB_CryoRifle", "PB_NukageBarrel"
    };

    static const string SCOPED[] =
    {
        "PB_Railgun", "BDPBattleRifle", "PB_CSSG", "Stormcast"
    };

    // ------------------------------------------------------------
    default
    {
        Inventory.MaxAmount 1;
    }

    // ------------------------------------------------------------
    // Helper: skip rotation for certain weapons
    private bool SkipRotation()
    {
        let weap = owner.player.readyWeapon;
        if (!weap) return true;
        Name cls = weap.GetClassName();
        for (int i = 0; i < NO_ROTATE.Size(); i++)
            if (cls == NO_ROTATE[i]) return true;
        return false;
    }

    // ------------------------------------------------------------
    // Helper: check if weapon is scoped
    private bool IsScoped()
    {
        let weap = owner.player.readyWeapon;
        if (!weap) return false;

        Name cls = weap.GetClassName();
        bool found = false;
        for (int i = 0; i < SCOPED.Size(); i++)
        {
            if (cls == SCOPED[i]) { found = true; break; }
        }
        if (!found) return false;

        let psp = owner.player.FindPSprite(PSP_WEAPON);
        if (!psp) return false;

        State st;

        st = weap.FindState("ZoomIn");
        if (st && weap.InStateSequence(psp.curState, st)) return true;

        st = weap.FindState("ZoomOut");
        if (st && weap.InStateSequence(psp.curState, st)) return true;

        st = weap.FindState("AltFire");
        if (st && weap.InStateSequence(psp.curState, st)) return true;

        return false;
    }

    // ------------------------------------------------------------
    // Wall detection
    bool bFacingWall(double distance = 24, double offsetZ = -12)
    {
        FLineTraceData wallcheck;
        owner.LineTrace(
            owner.angle,
            distance,
            owner.pitch,
            offsetz: owner.height + offsetZ,
            data: wallcheck
        );
        return (wallcheck.HitType == TRACE_HitWall);
    }

    // ------------------------------------------------------------
    // Helper: player alive?
    bool bIsPlayerAlive()
    {
        if (!owner || !owner.player) return false;
        return owner.player.health > 0;
    }

    // ------------------------------------------------------------
    // Helper: on ground? (works with any ZScript version)
    bool bIsOnFloor()
    {
        if (!owner) return false;
        return owner.Pos.Z == owner.FloorZ;
    }

    // ------------------------------------------------------------
    // Helper: linear interpolation (map)
    double map(double value, double fromLow, double fromHigh, double toLow, double toHigh)
    {
        if (fromLow == fromHigh) return toLow;
        double t = (value - fromLow) / (fromHigh - fromLow);
        return toLow + t * (toHigh - toLow);
    }

    // ------------------------------------------------------------
    override void DoEffect()
    {
        super.DoEffect();

        currentTickCount++;

        if (!owner || !owner.player)
            return;

        let weaponsprite = owner.player.FindPSprite(PSP_WEAPON);

        if (!(owner.player.weaponstate & wf_weaponbobbing))
            return;

        if (!weaponsprite)
            return;

        // --- Skip for special weapons ---
        if (SkipRotation())
        {
            weaponsprite.rotation = 0;
            if (offset)
                weaponsprite.y = weaponsprite.y - loweringAmount;
            return;
        }

        // --- Scoped weapons: no tilt ---
        if (IsScoped())
        {
            weaponsprite.rotation = 0;
            if (offset)
                weaponsprite.y = weaponsprite.y - loweringAmount;
            return;
        }

        // --- Fetch CVARs (optimised: every 35 tics) ---
        if (currentTickCount % 35 == 0)
        {
            rResistance = cvar.getcvar("wt_rollresistance", owner.player).getfloat();
            rVelocity = cvar.getcvar("wt_rollvelocity", owner.player).getfloat();
            rLimit = cvar.getcvar("wt_rollcap", owner.player).getfloat();
            rWallLoweringAmount = cvar.getcvar("wt_walllowering", owner.player).getfloat();

            limit = cvar.getcvar("wt_cap", owner.player).getbool();
            offset = cvar.getcvar("wt_offset", owner.player).getbool();
            lowering = cvar.getcvar("wt_lowering", owner.player).getbool();
            wallDetection = cvar.getcvar("wt_walldetection", owner.player).getbool();
        }

        // --- Weapon tilt calculation (original) ---
        aVelocity = atan2(owner.vel.y, owner.vel.x);
        direction = (sin(-owner.angle), cos(-owner.angle));
        velocityUnit = owner.vel.xy;
        currentRoll += (velocityUnit dot direction) * rVelocity;
        currentRoll *= rResistance;
        crABS = abs(currentRoll);

        // ======================== LEANING SYSTEM ========================
        if (bIsPlayerAlive())
        {
            // Read lean CVARs
            double leanAngle = sv_leanangle;   // server CVAR – global variable
            bool strafeLean = CVar.GetCVar('cl_strafelean', owner.player).GetBool();

            PlayerInfo pi = owner.player;

            let input = pi.cmd.buttons;
            let oldinput = pi.oldbuttons;

            bool strafe_left = (input & BT_MOVELEFT) && !(oldinput & BT_MOVELEFT);
            bool strafe_right = (input & BT_MOVERIGHT) && !(oldinput & BT_MOVERIGHT);
            bool unstrafe_left = !(input & BT_MOVELEFT) && (oldinput & BT_MOVELEFT);
            bool unstrafe_right = !(input & BT_MOVERIGHT) && (oldinput & BT_MOVERIGHT);

            bool lean_left = owner.CheckInventory('BT_LeanLeft', 1);
            bool lean_right = owner.CheckInventory('BT_LeanRight', 1);

            // --- Strafe‑lean toggle (cl_strafelean) with SLOW movement ---
            if (strafeLean && !last_strafelean)
            {
                if (input & BT_MOVELEFT)
                {
                    leantilt -= leanAngle;
                    if (bIsOnFloor())
                        owner.Thrust(12.0, owner.angle + 90.0);
                }
                if (input & BT_MOVERIGHT)
                {
                    leantilt += leanAngle;
                    if (bIsOnFloor())
                        owner.Thrust(12.0, owner.angle - 90.0);
                }
                owner.speed = 0.5;   // slow movement while leaning
            }
            else if (strafeLean)
            {
                if (strafe_right || unstrafe_left)
                {
                    leantilt += leanAngle;
                    if (bIsOnFloor())
                        owner.Thrust(12.0, owner.angle - 90.0);
                }
                if (strafe_left || unstrafe_right)
                {
                    leantilt -= leanAngle;
                    if (bIsOnFloor())
                        owner.Thrust(12.0, owner.angle + 90.0);
                }
                owner.speed = 0.5;
            }
            else if (last_strafelean)
            {
                if (bIsOnFloor())
                {
                    if (leantilt < 0.0)
                        owner.Thrust(12.0, owner.angle - 90.0);
                    else if (leantilt > 0.0)
                        owner.Thrust(12.0, owner.angle + 90.0);
                }
                leantilt = 0.0;
                owner.speed = 1.0;
            }
            // --- Q/E leaning ---
            else if ((lean_left && !last_leanleft) || (last_leanright && !lean_right))
            {
                leantilt -= leanAngle;
                if (bIsOnFloor())
                    owner.Thrust(12.0, owner.angle + 90.0);
            }
            else if ((lean_right && !last_leanright) || (last_leanleft && !lean_left))
            {
                leantilt += leanAngle;
                if (bIsOnFloor())
                    owner.Thrust(12.0, owner.angle - 90.0);
            }
            else if (!(lean_right || lean_left))
            {
                leantilt = 0.0;
            }

            last_strafelean = strafeLean;
            last_leanleft = lean_left;
            last_leanright = lean_right;

            // --- Visual effects: camera height, weapon offset, player height/scale ---
            PlayerPawn player = PlayerPawn(owner);

            pi.viewz += map(
                abs(leantilt),
                0.0, 90.0,
                0.0,
                -player.viewheight * pi.CrouchFactor
            );

            if (defaultattackzoffset == 0)
                defaultattackzoffset = player.attackzoffset;
            player.attackzoffset = map(
                abs(leantilt),
                0.0, 90.0,
                defaultattackzoffset,
                owner.height * -0.4
            );

            owner.height = map(
                abs(leantilt),
                0.0, 90.0,
                player.FullHeight * pi.CrouchFactor,
                owner.radius
            );
            owner.scale.y = map(
                abs(leantilt),
                0.0, 90.0,
                1.0,
                double(owner.radius) / player.FullHeight
            );

            // Movement slowdown while leaning
            if (abs(leantilt) > 1.0 && bIsOnFloor())
            {
                leandelay = 9;
                owner.vel *= 0.75;
            }
            else if (leandelay > 0)
            {
                leandelay--;
                owner.vel *= 0.75;
            }

            // Smooth leaning effect – faster response (doubled speed)
            leanlerp += (leantilt - leanlerp) * 0.2;   // was 0.1

            // Apply camera roll (this gives the visual tilt)
            owner.A_SetRoll(leanlerp, SPF_INTERPOLATE);
        }
        // ======================== END LEANING ========================

        // --- Weapon lowering (original) ---
        if (lowering)
        {
            double sidewaysMovement = abs(owner.player.cmd.sidemove);
            double targetLowering = 0;

            if (sidewaysMovement > 0)
                targetLowering = min(22.0, (owner.vel.length() * 1.5) + sidewaysMovement * 0.05);

            if (wallDetection && bFacingWall())
            {
                targetLowering = min(30.0, targetLowering + rWallLoweringAmount);
                duckAmount = clamp(duckAmount + 6, 0, 30);
                targetLowering = max(targetLowering, duckAmount);
            }
            else
            {
                duckAmount *= 0.9;
            }

            loweringSmoothing = 0.2;
            loweringAmount += (targetLowering - loweringAmount) * loweringSmoothing;

            if (offset)
                weaponsprite.y = weaponsprite.y + crABS + loweringAmount;
            else
                weaponsprite.y = weaponsprite.y + loweringAmount;
        }
        else if (offset)
        {
            weaponsprite.y = weaponsprite.y + crABS;
        }

        // --- Roll cap (optional) ---
        if (limit && currentRoll > rLimit)
            currentRoll = rLimit;

        // --- Apply final rotation to weapon sprite (no leaning addition) ---
        weaponsprite.rotation = currentRoll;
    }
}