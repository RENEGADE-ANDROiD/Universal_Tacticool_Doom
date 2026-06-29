/*
Part of Universal Weapon Tilter by generic name guy.
You can download a copy of the source code or contribute to the project on GitHub at https://github.com/generic-name-guy/universal-weapon-tilt-gz/
This is code licensed under Unlicense, so do whatever you want with it, i don't care.
*/
// PLUS //
/////////////////////////////////////////////////////////
/////    Strafing Weapon Tilt + Lowering        /////
///// 			For Project Brutaltiy				///// 
/////        	 by Dithered OutPut					///// 
/////////////////////////////////////////////////////////

/* ============================================================================
   Universal Weapon Tilter + Complete Leaning (Q/E + Strafe-Lean Toggle)
   Camera roll for leaning, weapon tilt only from movement
   ============================================================================ */

class WeaponTilterInventory : Inventory
{
    // ------------------------------------------------------------
    // Tactical pose state (compute in DoEffect, apply in WorldTick)
    double currentRoll;
    double smoothedWeaponRoll;
    double prevStrafeDot;
    double loweringAmount;
    double motionEnableBlend;
    int strafeStableTicks;

    double outputRoll;
    double outputLowerY;
    bool poseActive;
    bool cvEnabled;

    double lastAppliedRoll;
    double lastAppliedY;

    // Cached CVARs
    float cvRollResistance;
    float cvRollVelocity;
    float cvRollCap;
    float cvLoweringIntensity;
    float cvTiltMovingMin;
    bool cvCapRoll;
    bool cvOffset;
    bool cvLowering;
    bool cvTiltMoving;
    bool cvTiltReady;

    int currentTickCount;

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
        "PB_Minigun", "PB_CryoRifle", "PB_NukageBarrel", "BattleAxe", "DragonSlayer", "Stormcast"
    };

    static const string SCOPED[] =
    {
        "PB_Railgun", "BDPBattleRifle", "PB_CSSG", "TDRWPN09"
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
    // Gating: is PSP_WEAPON in a typical ready loop?
    private bool IsWeaponReadyForTilt(Weapon weap, PSprite psp)
    {
        if (!weap || !psp || !psp.CurState) return false;

        State st = weap.FindState("Ready");
        if (st && weap.InStateSequence(psp.curState, st)) return true;

        st = weap.FindState("Hold");
        if (st && weap.InStateSequence(psp.curState, st)) return true;

        return false;
    }

    private bool IsSwitchState(Weapon weap, PSprite psp)
    {
        if (!weap || !psp || !psp.CurState)
            return false;

        static const statelabel switchLabels[] =
        {
            "Select", "Deselect"
        };

        for (int i = 0; i < switchLabels.Size(); ++i)
        {
            State st = weap.FindState(switchLabels[i]);
            if (st && weap.InStateSequence(psp.CurState, st))
                return true;
        }

        State upState = weap.GetUpState();
        State downState = weap.GetDownState();
        if (upState && weap.InStateSequence(psp.CurState, upState))
            return true;
        if (downState && weap.InStateSequence(psp.CurState, downState))
            return true;

        return false;
    }

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
    // Helper: player alive?
    bool bIsPlayerAlive()
    {
        if (!owner || !owner.player) return false;
        return owner.player.health > 0;
    }

    // ------------------------------------------------------------
    // Helper: on ground? (compat-safe across UZDoom builds)
    bool bIsOnFloor()
    {
        if (!owner) return false;
        if (owner.bONMOBJ || owner.bMBFBOUNCER)
            return true;
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

    private bool HasStrafeActivity(PlayerInfo pi, double strafeDot)
    {
        if (!pi)
            return false;
        if (abs(pi.cmd.sidemove) > 0)
            return true;
        return abs(strafeDot) > 0.22;
    }

    private bool BlocksStrafeMotion(PlayerInfo pi, double forwardDot)
    {
        if (!pi)
            return true;
        if (abs(pi.cmd.forwardmove) > 0)
            return true;
        return abs(forwardDot) > 0.42;
    }

    private void UpdateMotionBlend(PlayerInfo pi, double strafeDot, double forwardDot)
    {
        if (BlocksStrafeMotion(pi, forwardDot) || !HasStrafeActivity(pi, strafeDot))
        {
            strafeStableTicks = 0;
            motionEnableBlend *= 0.50;
            if (motionEnableBlend < 0.02)
                motionEnableBlend = 0;
            return;
        }

        strafeStableTicks++;
        if (strafeStableTicks < 3)
            return;

        motionEnableBlend += (1.0 - motionEnableBlend) * 0.12;
    }

    private void RefreshCvars(PlayerInfo pi)
    {
        cvRollResistance = cvar.getcvar("wt_rollresistance", pi).getfloat();
        cvRollVelocity = cvar.getcvar("wt_rollvelocity", pi).getfloat();
        cvRollCap = cvar.getcvar("wt_rollcap", pi).getfloat();
        cvLoweringIntensity = cvar.getcvar("wt_lowering_intensity", pi).getfloat();
        cvTiltMovingMin = cvar.getcvar("wt_tilt_moving_min", pi).getfloat();

        cvEnabled = true; // global enable not present; keep addon active.
        cvCapRoll = cvar.getcvar("wt_cap", pi).getbool();
        cvOffset = cvar.getcvar("wt_offset", pi).getbool();
        cvLowering = cvar.getcvar("wt_lowering", pi).getbool();
        cvTiltMoving = cvar.getcvar("wt_tilt_moving", pi).getbool();
        cvTiltReady = cvar.getcvar("wt_tilt_ready", pi).getbool();

        cvLoweringIntensity = clamp(cvLoweringIntensity, 0.0, 2.0);
    }

    private bool ShouldBlockForSafety(Weapon weap, PSprite psp)
    {
        if (!owner || !owner.player || !weap || !psp)
            return true;
        if (SkipRotation())
            return true;
        if (IsScoped())
            return true;
        if (IsSwitchState(weap, psp))
            return true;
        return false;
    }

    private void ClearAppliedPose(PSprite psp)
    {
        if (!psp)
            return;

        if (lastAppliedY != 0)
        {
            psp.Y -= lastAppliedY;
            lastAppliedY = 0;
        }

        if (lastAppliedRoll != 0)
        {
            psp.Rotation -= lastAppliedRoll;
            lastAppliedRoll = 0;
        }
    }

    void ApplyPose(PlayerInfo pi)
    {
        if (!pi)
            return;

        let psp = pi.FindPSprite(PSP_WEAPON);
        if (!psp)
            return;

        ClearAppliedPose(psp);

        if (!poseActive || !cvEnabled)
            return;

        psp.Rotation += outputRoll;
        psp.Y += outputLowerY;
        lastAppliedRoll = outputRoll;
        lastAppliedY = outputLowerY;
    }

    // ------------------------------------------------------------
    override void DoEffect()
    {
        super.DoEffect();
        currentTickCount++;
        outputRoll = 0;
        outputLowerY = 0;
        poseActive = false;

        if (!owner || !owner.player)
            return;

        let weaponsprite = owner.player.FindPSprite(PSP_WEAPON);
        let wpn = owner.player.readyWeapon;
        if (!weaponsprite || !wpn)
            return;

        if (currentTickCount == 1 || currentTickCount % 4 == 0)
            RefreshCvars(owner.player);

        bool doStrafeMotion = (owner.player.weaponstate & wf_weaponbobbing) != 0;
        bool blocked = ShouldBlockForSafety(Weapon(wpn), weaponsprite);
        bool ready = IsWeaponReadyForTilt(Weapon(wpn), weaponsprite);

        double speedXY = owner.Vel.XY.Length();
        Vector2 strafeDir = (sin(-owner.angle), cos(-owner.angle));
        Vector2 forwardDir = (cos(owner.angle), sin(owner.angle));
        double strafeDot = owner.Vel.X * strafeDir.X + owner.Vel.Y * strafeDir.Y;
        double forwardDot = owner.Vel.X * forwardDir.X + owner.Vel.Y * forwardDir.Y;

        bool allowMotion = !blocked && doStrafeMotion;
        if (cvTiltMoving)
            allowMotion = allowMotion && (speedXY > cvTiltMovingMin);
        if (cvTiltReady)
            allowMotion = allowMotion && ready;

        if (!allowMotion)
        {
            strafeStableTicks = 0;
            motionEnableBlend *= 0.50;
            if (motionEnableBlend < 0.02)
                motionEnableBlend = 0;
        }
        else
        {
            UpdateMotionBlend(owner.player, strafeDot, forwardDot);
        }

        bool allowRoll = allowMotion && motionEnableBlend > 0.08;
        if (allowRoll)
        {
            if (prevStrafeDot * strafeDot < 0. && abs(strafeDot) > 0.02 && abs(prevStrafeDot) > 0.02)
                currentRoll *= 0.55;

            currentRoll += strafeDot * cvRollVelocity * motionEnableBlend;
            currentRoll *= cvRollResistance;
            if (cvCapRoll)
                currentRoll = clamp(currentRoll, -cvRollCap, cvRollCap);
        }
        else
        {
            currentRoll *= 0.62;
            if (motionEnableBlend < 0.02)
                currentRoll = 0;
        }

        prevStrafeDot = strafeDot;
        smoothedWeaponRoll = smoothedWeaponRoll * 0.65 + currentRoll * 0.35;
        outputRoll = smoothedWeaponRoll * motionEnableBlend;
        double crABS = abs(outputRoll);

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

        // --- Weapon lowering (strafe/movement only) ---
        if (cvLowering)
        {
            double sidewaysMovement = abs(owner.player.cmd.sidemove);
            double targetLowering = 0;

            if (sidewaysMovement > 0)
                targetLowering = min(22.0, (speedXY * 1.5) + sidewaysMovement * 0.05);

            targetLowering *= cvLoweringIntensity;
            loweringAmount += (targetLowering - loweringAmount) * 0.2;
            if (!allowMotion && motionEnableBlend < 0.08)
                loweringAmount *= 0.75;

            outputLowerY = loweringAmount;
            if (cvOffset)
                outputLowerY += crABS;
        }
        else if (cvOffset)
        {
            outputLowerY = crABS;
            loweringAmount = 0;
        }
        else
        {
            loweringAmount = 0;
        }

        poseActive = abs(outputRoll) > 0.05 || abs(outputLowerY) > 0.1;
    }
}