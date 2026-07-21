/*
Part of Universal Weapon Tilter by generic name guy.
Universal runtime weapon tilt + pendulum lowering for any GZDoom/UZDoom gameplay mod.
Techniques adapted from PBWP (see note.md). PB/Brutal-family extras are gated by wt_pb_compat.
Multi-TC idle/combat labels: see **TC_STATE_LABELS.md** (survey + hybrid allowlist/fallback).
*/

class WeaponTilterInventory : Inventory
{
    double currentRoll;
    double smoothedWeaponRoll;
    double prevStrafeDot;
    double motionEnableBlend;

    double outputRoll;
    double smoothedPendulumDip;
    double lastAppliedRoll;
    double lastAppliedBillboardX;
    double lastAppliedDip;
    double baselineWeaponY;

    bool poseActive;
    bool cvEnabled;
    bool hasBaselineWeaponY;
    bool restoreDipThisTick;
    bool rollOnlyWeapon;

    Name lastWeaponClass;
    int currentTickCount;
    double lastViewzLeanOffset;

    float cvRollResistance;
    float cvRollVelocity;
    float cvRollCap;
    float cvLoweringIntensity;
    float cvTiltMovingMin;
    float cvTiltSmoothing;
    bool cvCapRoll;
    bool cvLowering;
    bool cvTiltMoving;
    bool cvTiltReady;
    bool pbCompatActive;

    bool last_strafelean;
    bool last_leanleft, last_leanright;
    double leantilt, leanlerp;
    int leandelay;
    double defaultattackzoffset;

    // Example exclusions — edit for your target mod (see README).
    static const string NO_ROTATE[] =
    {
        "PB_Minigun", "PB_CryoRifle", "PB_NukageBarrel", "BattleAxe", "DragonSlayer", "Stormcast"
    };

    // Weapons that jitter if Y is modified each tic (roll-only, no pendulum dip).
    static const string ROLL_ONLY[] =
    {
        "Stormcast"
    };

    static const string SCOPED[] =
    {
        "PB_Railgun", "BDPBattleRifle", "PB_CSSG", "TDRWPN09"
    };

    // Optional PB / Brutal Pack / Brutal Doom / Schism compat (wt_pb_compat Auto or On).
    static const string PB_NO_ROTATE[] =
    {
        "PB_BFG9000", "PB_BFGMKIV", "PB_BFGBeam", "PB_BLACKHOLE", "PB_Unmaker",
        "MastermindChaingun"
    };

    static const string PB_ROLL_ONLY[] =
    {
        "ThunderCrossbow"
    };

    static const string PB_SCOPED[] =
    {
        "PB_BDPRailgun", "PB_MetalSniper", "PB_XM21", "PBX_BattleRifle",
        "PB_LeverAction", "Gauss", "HeavySniperRifle", "PB_GaussCannon"
    };

    default
    {
        Inventory.MaxAmount 1;
        +INVENTORY.UNDROPPABLE
    }

    private bool PbCompatEnabled(PlayerInfo pi)
    {
        int mode = cvar.getcvar("wt_pb_compat", pi).getint();
        if (mode == 0)
            return false;
        if (mode == 2)
            return true;

        let handler = WeaponTilterEventHandler(EventHandler.Find("WeaponTilterEventHandler"));
        return handler && handler.IsBDFamilyDetected();
    }

    private bool IsPbExtendedIdleState(Weapon weap, PSprite psp)
    {
        static const statelabel pbIdle[] =
        {
            "ReadyAim", "Ready_ADS", "BDReady3", "BDReadyADS", "ReadyRaised",
            "ReallyReady2Loop", "ReallyReady3", "ActuallyReady3",
            "Ready5", "ReadySettle", "ReadyToFire_Red", "ReadyToFireDrum",
            "ReadyMissile", "JavelinReady3", "ReadyDualWield", "ReadyToFireDualWield",
            "RealReady_Reload"
        };
        for (int i = 0; i < pbIdle.Size(); ++i)
        {
            if (InWeaponStateSequence(weap, psp, pbIdle[i]))
                return true;
        }
        return false;
    }

    private bool IsPbReadyForOverlay(Weapon weap, PSprite psp, PlayerInfo pi)
    {
        if (IsWeaponIdleForTilt(weap, psp, pi, false))
            return true;

        static const statelabel pbReady[] =
        {
            "Ready3", "ReadyAim", "Ready_ADS", "BDReady3", "BDReadyADS", "ReadyRaised",
            "ReallyReady2Loop", "ReallyReady3", "ActuallyReady3"
        };
        for (int i = 0; i < pbReady.Size(); ++i)
        {
            if (InWeaponStateSequence(weap, psp, pbReady[i]))
                return true;
        }
        return false;
    }

    private bool IsPbScopedNow(Weapon weap, PSprite psp)
    {
        if (!owner || !weap || !psp || !psp.CurState)
            return false;

        Name cls = weap.GetClassName();
        bool listed = false;
        for (int i = 0; i < SCOPED.Size(); i++)
        {
            if (cls == SCOPED[i])
            {
                listed = true;
                break;
            }
        }
        if (!listed)
        {
            for (int i = 0; i < PB_SCOPED.Size(); i++)
            {
                if (cls == PB_SCOPED[i])
                {
                    listed = true;
                    break;
                }
            }
        }
        if (!listed)
            return false;

        if (HasInvToken('Zoomed') || HasInvToken('ADSMode'))
            return true;

        static const statelabel scopedNow[] =
        {
            "ZoomIn", "ZoomOut", "Ready_ADS", "BDReadyADS", "ZoomFire",
            "ScopedFire", "Fire_ADS", "ZoomLoop", "FireZoom", "FireZoomed"
        };

        for (int i = 0; i < scopedNow.Size(); ++i)
        {
            if (InWeaponStateSequence(weap, psp, scopedNow[i]))
                return true;
        }
        return weap.FOVScale < 0.99;
    }

    private bool ShouldBlockPbSafety(Weapon weap, PSprite psp, PlayerInfo pi)
    {
        if (IsPbScopedNow(weap, psp))
            return true;

        let ov10 = pi.GetPSprite(10);
        let ov11 = pi.GetPSprite(11);
        bool hasOverlayActions = (ov10 && ov10.CurState) || (ov11 && ov11.CurState);
        if (hasOverlayActions && !IsPbReadyForOverlay(weap, psp, pi))
            return true;

        if (HasInvToken('GoFatality') || HasInvToken('ExecutionToken'))
            return true;
        if (HasInvToken('Kicking') || HasInvToken('UseEquipment')
            || HasInvToken('ToggleEquipment'))
            return true;
        if (HasInvToken('PlayerIsThrowingAGrenade')
            || HasInvToken('PlayerIsThrowingAMolotovCocktail'))
            return true;
        if (HasInvToken('DoShoulderCannon') || HasInvToken('DoGloryMelee')
            || HasInvToken('PB_LockScreenTilt'))
            return true;

        return false;
    }

    private void ClearPbOverlayRoll(PlayerInfo pi)
    {
        if (!pi)
            return;

        let o10 = pi.FindPSprite(10); if (o10) o10.Rotation = 0;
        let o11 = pi.FindPSprite(11); if (o11) o11.Rotation = 0;
        let o60 = pi.FindPSprite(60); if (o60) o60.Rotation = 0;
        let o61 = pi.FindPSprite(61); if (o61) o61.Rotation = 0;
        let o63 = pi.FindPSprite(63); if (o63) o63.Rotation = 0;
        let o64 = pi.FindPSprite(64); if (o64) o64.Rotation = 0;
    }

    private void ApplyPbOverlayRoll(PlayerInfo pi, double roll)
    {
        if (!pi)
            return;

        let o10 = pi.FindPSprite(10); if (o10) o10.Rotation = roll;
        let o11 = pi.FindPSprite(11); if (o11) o11.Rotation = roll;
        let o60 = pi.FindPSprite(60); if (o60) o60.Rotation = roll;
        let o61 = pi.FindPSprite(61); if (o61) o61.Rotation = roll;
        let o63 = pi.FindPSprite(63); if (o63) o63.Rotation = roll;
        let o64 = pi.FindPSprite(64); if (o64) o64.Rotation = roll;
    }

    private bool HasInvToken(Name token)
    {
        let item = owner.Inv;
        while (item)
        {
            if (item.GetClassName() == token)
                return true;
            item = item.Inv;
        }
        return false;
    }

    private bool IsPbWpCaWeaponBase(Weapon weap)
    {
        class<Object> pbBase = Object.FindClass('PBWP_CA_WeaponBase');
        return weap && pbBase && weap is pbBase;
    }

    private bool InWeaponStateSequence(Weapon weap, PSprite psp, statelabel label)
    {
        if (!weap || !psp || !psp.CurState)
            return false;
        State st = weap.FindState(label);
        return st && weap.InStateSequence(psp.CurState, st);
    }

    private void ResetRollState()
    {
        currentRoll = 0;
        smoothedWeaponRoll = 0;
        prevStrafeDot = 0;
        outputRoll = 0;
        lastAppliedRoll = 0;
        lastAppliedBillboardX = 0;
    }

    private void DiscardPendulumDipState()
    {
        lastAppliedDip = 0;
        smoothedPendulumDip = 0;
        hasBaselineWeaponY = false;
    }

    private void RestorePendulumDip(PSprite psp)
    {
        if (psp)
        {
            if (hasBaselineWeaponY)
                psp.Y = baselineWeaponY;
            else if (lastAppliedDip > 0)
                psp.Y -= lastAppliedDip;
        }
        DiscardPendulumDipState();
    }

    private void ApplyPendulumDip(PSprite psp, double dip)
    {
        if (!psp)
            return;

        if (hasBaselineWeaponY && lastAppliedDip > 0.05)
        {
            double expectedY = baselineWeaponY + lastAppliedDip;
            if (abs(psp.Y - expectedY) > 2.0)
            {
                baselineWeaponY = psp.Y;
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
            psp.Y = baselineWeaponY + dip;
            lastAppliedDip = dip;
        }
        else
        {
            psp.Y = baselineWeaponY;
            lastAppliedDip = 0;
        }
    }

    private bool SkipRotation(Weapon weap)
    {
        if (!weap)
            return true;

        Name cls = weap.GetClassName();
        for (int i = 0; i < NO_ROTATE.Size(); i++)
        {
            if (cls == NO_ROTATE[i])
                return true;
        }

        if (pbCompatActive)
        {
            for (int i = 0; i < PB_NO_ROTATE.Size(); i++)
            {
                if (cls == PB_NO_ROTATE[i])
                    return true;
            }
        }

        return false;
    }

    private bool UsesRollOnlyMotion(Weapon weap)
    {
        if (!weap)
            return false;

        Name cls = weap.GetClassName();
        for (int i = 0; i < ROLL_ONLY.Size(); i++)
        {
            if (cls == ROLL_ONLY[i])
                return true;
        }

        if (pbCompatActive)
        {
            if (IsPbWpCaWeaponBase(weap))
                return true;
            for (int i = 0; i < PB_ROLL_ONLY.Size(); i++)
            {
                if (cls == PB_ROLL_ONLY[i])
                    return true;
            }
        }

        return false;
    }

    // Core idle labels — present in virtually every GZDoom mod (vanilla + TC survey).
    private bool IsCoreIdleState(Weapon weap, PSprite psp)
    {
        static const statelabel coreIdle[] =
        {
            "Ready", "Hold", "ReadyLoop", "Readyloop", "Idle", "GunReady", "WaitReady"
        };
        for (int i = 0; i < coreIdle.Size(); ++i)
        {
            if (InWeaponStateSequence(weap, psp, coreIdle[i]))
                return true;
        }
        return false;
    }

    // Common TC variants (Brutal Doom family, Ashes, Bloom, etc.) — see TC_STATE_LABELS.md.
    private bool IsExtendedIdleState(Weapon weap, PSprite psp)
    {
        static const statelabel extendedIdle[] =
        {
            "Ready2", "Ready3", "Ready4", "RealReady", "ReallyReady", "ReallyReady2",
            "ReadyToFire", "ReadyToFire2", "ReadyToFireAgain",
            "ReadyNormal", "ReadyLoaded", "ReadyFull", "ReadyNoAmmo", "IdleNoAmmo", "NoBuzzing",
            "SelectContinue", "SelectAnimation", "SelectReady",
            "ReadyZoom", "ReadyZoomed", "ScopedReady"
        };
        for (int i = 0; i < extendedIdle.Size(); ++i)
        {
            if (InWeaponStateSequence(weap, psp, extendedIdle[i]))
                return true;
        }
        return false;
    }

    private bool IsGenericReadyFallback(Weapon weap, PSprite psp)
    {
        if (!weap || !weap.FindState("RealReady"))
            return InWeaponStateSequence(weap, psp, "Ready");
        return false;
    }

    // Allowlist first; wf_weaponready fallback when not in combat/switch (unknown labels).
    private bool IsWeaponIdleForTilt(Weapon weap, PSprite psp, PlayerInfo pi, bool strictReadyOnly)
    {
        if (!weap || !psp || !psp.CurState)
            return false;

        if (IsCoreIdleState(weap, psp))
            return true;

        if (!strictReadyOnly)
        {
            if (IsExtendedIdleState(weap, psp))
                return true;
            if (pbCompatActive && IsPbExtendedIdleState(weap, psp))
                return true;
            if (IsGenericReadyFallback(weap, psp))
                return true;
            if (!IsCombatWeaponState(weap, psp) && !IsSwitchState(weap, psp))
            {
                if ((pi.weaponstate & wf_weaponready) != 0)
                    return true;
            }
        }

        return false;
    }

    private bool IsRecognizedIdleState(Weapon weap, PSprite psp)
    {
        return IsCoreIdleState(weap, psp)
            || IsExtendedIdleState(weap, psp)
            || (pbCompatActive && IsPbExtendedIdleState(weap, psp))
            || IsGenericReadyFallback(weap, psp);
    }

    private bool IsSwitchState(Weapon weap, PSprite psp)
    {
        if (!weap || !psp || !psp.CurState)
            return false;

        if (IsRecognizedIdleState(weap, psp))
            return false;

        static const statelabel switchLabels[] =
        {
            "Select", "Deselect"
        };

        for (int i = 0; i < switchLabels.Size(); ++i)
        {
            if (InWeaponStateSequence(weap, psp, switchLabels[i]))
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

    private bool IsCombatWeaponState(Weapon weap, PSprite psp)
    {
        if (!weap || !psp || !psp.CurState)
            return false;

        static const statelabel combatLabels[] =
        {
            "Fire", "Fire2", "Fire3", "HoldFire", "AltFire", "AltFire1", "AltFire2",
            "Melee", "Melee2", "Punch", "Kick", "Stomp",
            "Reload", "Reloading", "ReloadLoop", "ReloadLoop2", "Reload2",
            "Pump", "Slide", "Burst", "Charge", "ChargeLoop", "Attack", "Windup"
        };

        for (int i = 0; i < combatLabels.Size(); ++i)
        {
            if (InWeaponStateSequence(weap, psp, combatLabels[i]))
                return true;
        }
        return false;
    }

    private bool IsScoped(Weapon weap, PSprite psp)
    {
        if (pbCompatActive && IsPbScopedNow(weap, psp))
            return true;

        if (!weap || !psp || !psp.CurState)
            return false;

        Name cls = weap.GetClassName();
        bool listed = false;
        for (int i = 0; i < SCOPED.Size(); i++)
        {
            if (cls == SCOPED[i])
            {
                listed = true;
                break;
            }
        }
        if (pbCompatActive && !listed)
        {
            for (int i = 0; i < PB_SCOPED.Size(); i++)
            {
                if (cls == PB_SCOPED[i])
                {
                    listed = true;
                    break;
                }
            }
        }

        static const statelabel scopedLabels[] =
        {
            "ZoomIn", "ZoomOut", "ReadyZoom", "ZoomLoop",
            "FireZoom", "FireZoomed", "AltFire"
        };

        for (int i = 0; i < scopedLabels.Size(); ++i)
        {
            if (InWeaponStateSequence(weap, psp, scopedLabels[i]))
                return listed || weap.FOVScale < 0.99;
        }

        return listed && weap.FOVScale < 0.99;
    }

    private bool ShouldBlockForSafety(Weapon weap, PSprite psp, PlayerInfo pi)
    {
        if (!owner || !owner.player || !weap || !psp)
            return true;
        if (SkipRotation(weap))
            return true;
        if (IsScoped(weap, psp))
            return true;
        if (pbCompatActive && ShouldBlockPbSafety(weap, psp, pi))
            return true;
        if (IsSwitchState(weap, psp))
            return true;
        if (IsCombatWeaponState(weap, psp))
            return true;
        return false;
    }

    private bool WeaponUsesBillboardSprite(Weapon weap)
    {
        return weap && weap.bFORCEXYBILLBOARD;
    }

    private double ComputePendulumDipTarget(double displayRoll, double strafeDrive, PlayerInfo pi, bool allowLowering)
    {
        if (!allowLowering || !cvLowering)
            return 0;

        double absRoll = abs(displayRoll);
        // Wait until roll has committed so dip doesn't lead with a wrong-side slam.
        if (absRoll < 0.55)
            return 0;

        bool strafeInput = abs(pi.cmd.sidemove) > 0 || abs(strafeDrive) > 0.05;
        if (!strafeInput)
            return 0;

        double scale = max(0.5, cvLoweringIntensity);
        double dip = (5.5 + absRoll * 7.5) * scale;
        // Keep left/right dip closer — old left-heavy bias exaggerated wrong-start look.
        if (displayRoll < 0)
            dip += absRoll * 3.2 * scale;
        else
            dip += absRoll * 2.4 * scale;

        return min(dip, 26.0);
    }

    private void ClearAppliedRollAndBillboard(PSprite psp)
    {
        if (!psp)
            return;

        if (lastAppliedBillboardX != 0)
        {
            psp.X -= lastAppliedBillboardX;
            lastAppliedBillboardX = 0;
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

        ClearAppliedRollAndBillboard(psp);

        if (restoreDipThisTick || !poseActive || !cvEnabled)
        {
            RestorePendulumDip(psp);
            if (pbCompatActive)
                ClearPbOverlayRoll(pi);
            restoreDipThisTick = false;
            return;
        }

        let wpn = Weapon(pi.ReadyWeapon);
        double applyRoll = outputRoll;
        double applyX = 0;

        if (WeaponUsesBillboardSprite(wpn))
        {
            applyX = outputRoll * 4.8;
            applyRoll = 0;
        }

        psp.Rotation += applyRoll;
        lastAppliedRoll = applyRoll;

        if (applyX != 0)
        {
            psp.X += applyX;
            lastAppliedBillboardX = applyX;
        }

        if (rollOnlyWeapon)
            RestorePendulumDip(psp);
        else
            ApplyPendulumDip(psp, smoothedPendulumDip);

        if (pbCompatActive)
        {
            double overlayRoll = applyRoll != 0 ? applyRoll : outputRoll;
            ApplyPbOverlayRoll(pi, overlayRoll);
        }
    }

    private void RefreshCvars(PlayerInfo pi)
    {
        cvEnabled = cvar.getcvar("wt_enable", pi).getbool();
        cvRollResistance = cvar.getcvar("wt_rollresistance", pi).getfloat();
        cvRollVelocity = cvar.getcvar("wt_rollvelocity", pi).getfloat();
        cvRollCap = cvar.getcvar("wt_rollcap", pi).getfloat();
        cvLoweringIntensity = cvar.getcvar("wt_lowering_intensity", pi).getfloat();
        cvTiltMovingMin = cvar.getcvar("wt_tilt_moving_min", pi).getfloat();
        cvTiltSmoothing = cvar.getcvar("wt_tilt_smoothing", pi).getfloat();
        cvCapRoll = cvar.getcvar("wt_cap", pi).getbool();
        cvLowering = cvar.getcvar("wt_lowering", pi).getbool();
        cvTiltMoving = cvar.getcvar("wt_tilt_moving", pi).getbool();
        cvTiltReady = cvar.getcvar("wt_tilt_ready", pi).getbool();
        pbCompatActive = PbCompatEnabled(pi);

        cvRollResistance = clamp(cvRollResistance, 0.08, 0.70);
        cvLoweringIntensity = clamp(cvLoweringIntensity, 0.0, 2.5);
        cvTiltSmoothing = clamp(cvTiltSmoothing, 0.20, 0.95);
        if (cvRollCap < 3.0) cvRollCap = 3.0;
    }

    bool bIsPlayerAlive()
    {
        return owner && owner.player && owner.player.health > 0;
    }

    bool bIsOnFloor()
    {
        if (!owner)
            return false;
        if (owner.bONMOBJ || owner.bMBFBOUNCER)
            return true;
        return owner.Pos.Z == owner.FloorZ;
    }

    double map(double value, double fromLow, double fromHigh, double toLow, double toHigh)
    {
        if (fromLow == fromHigh)
            return toLow;
        double t = (value - fromLow) / (fromHigh - fromLow);
        return toLow + t * (toHigh - toLow);
    }

    private void RestoreLeanBodyDefaults(PlayerPawn player, PlayerInfo pi)
    {
        if (lastViewzLeanOffset != 0)
        {
            pi.viewz -= lastViewzLeanOffset;
            lastViewzLeanOffset = 0;
        }

        if (defaultattackzoffset != 0)
            player.attackzoffset = defaultattackzoffset;

        owner.height = player.FullHeight * pi.CrouchFactor;
        owner.scale.y = 1.0;
    }

    override void DoEffect()
    {
        super.DoEffect();
        currentTickCount++;
        outputRoll = 0;
        poseActive = false;
        restoreDipThisTick = false;
        rollOnlyWeapon = false;

        if (!owner || !owner.player)
            return;

        let pi = owner.player;
        let psp = pi.FindPSprite(PSP_WEAPON);
        let wpn = pi.ReadyWeapon;
        if (!psp || !wpn)
            return;

        if (currentTickCount <= 8 || currentTickCount % 4 == 0)
            RefreshCvars(pi);

        Name weaponClass = wpn.GetClassName();
        if (weaponClass != lastWeaponClass)
        {
            ResetRollState();
            DiscardPendulumDipState();
            motionEnableBlend = 1.0;
            lastWeaponClass = weaponClass;
        }

        if (pi.PendingWeapon != WP_NOCHANGE && pi.PendingWeapon != null
            && pi.PendingWeapon.GetClassName() != weaponClass)
        {
            ResetRollState();
            restoreDipThisTick = true;
            smoothedPendulumDip = 0;
            return;
        }

        if (!cvEnabled)
        {
            ResetRollState();
            restoreDipThisTick = true;
            smoothedPendulumDip = 0;
            return;
        }

        let weap = Weapon(wpn);
        bool blocked = ShouldBlockForSafety(weap, psp, pi);
        bool idle = IsWeaponIdleForTilt(weap, psp, pi, cvTiltReady);
        rollOnlyWeapon = UsesRollOnlyMotion(weap);

        bool engineBob = (pi.weaponstate & wf_weaponbobbing) != 0;
        bool allowMotion = !blocked && (idle || engineBob);
        if (cvTiltReady)
            allowMotion = !blocked && idle;

        double speedXY = owner.Vel.XY.Length();
        // Positive cmd.sidemove = strafe right (Doom convention).
        double strafeInput = pi.cmd.sidemove / 10240.0;
        // Right-lateral axis (matches sidemove sign). Old left-axis velocity drive
        // briefly rolled the opposite way until momentum caught up.
        Vector2 rightDir = (sin(owner.angle), -cos(owner.angle));
        double strafeDot = owner.Vel.X * rightDir.X + owner.Vel.Y * rightDir.Y;

        // Input wins while strafing; velocity only fills in with no sidemove.
        double strafe = strafeInput;
        if (abs(strafeInput) < 0.08 && abs(strafeDot) > 1.0)
            strafe = clamp(strafeDot * 0.10, -1.5, 1.5);

        if (blocked)
        {
            currentRoll *= 0.75;
            smoothedWeaponRoll *= 0.75;
            motionEnableBlend += (0.0 - motionEnableBlend) * 0.35;
            restoreDipThisTick = true;
            smoothedPendulumDip *= 0.82;
            if (smoothedPendulumDip < 0.05)
                smoothedPendulumDip = 0;
        }
        else
        {
            if (cvTiltMoving)
                allowMotion = allowMotion && (speedXY > cvTiltMovingMin);

            if (allowMotion)
                motionEnableBlend += (1.0 - motionEnableBlend) * 0.35;
            else
                motionEnableBlend += (0.0 - motionEnableBlend) * 0.35;

            if (allowMotion)
            {
                if (prevStrafeDot * strafe < 0.
                    && abs(strafe) > 0.02 && abs(prevStrafeDot) > 0.02)
                {
                    currentRoll *= 0.88;
                }

                currentRoll += strafe * cvRollVelocity * motionEnableBlend;
                currentRoll *= cvRollResistance;
                if (cvCapRoll)
                    currentRoll = clamp(currentRoll, -cvRollCap, cvRollCap);
            }
            else
            {
                currentRoll *= 0.75;
            }

            prevStrafeDot = strafe;

            double tiltS = cvTiltSmoothing;
            smoothedWeaponRoll = smoothedWeaponRoll * tiltS + currentRoll * (1.0 - tiltS);
            outputRoll = smoothedWeaponRoll;

            bool allowLowering = allowMotion && !rollOnlyWeapon;
            double dipTarget = ComputePendulumDipTarget(outputRoll, strafe, pi, allowLowering);
            double dipRate = dipTarget > smoothedPendulumDip ? 0.36 : 0.30;
            smoothedPendulumDip += (dipTarget - smoothedPendulumDip) * dipRate;
            if (smoothedPendulumDip <= 0.05)
                smoothedPendulumDip = 0;

            poseActive = abs(outputRoll) > 0.05 || smoothedPendulumDip > 0.05;
        }

        // ======================== LEANING SYSTEM ========================
        if (bIsPlayerAlive())
        {
            double leanAngle = sv_leanangle;
            bool strafeLean = CVar.GetCVar('cl_strafelean', pi).GetBool();

            let input = pi.cmd.buttons;
            let oldinput = pi.oldbuttons;

            bool strafe_left = (input & BT_MOVELEFT) && !(oldinput & BT_MOVELEFT);
            bool strafe_right = (input & BT_MOVERIGHT) && !(oldinput & BT_MOVERIGHT);
            bool unstrafe_left = !(input & BT_MOVELEFT) && (oldinput & BT_MOVELEFT);
            bool unstrafe_right = !(input & BT_MOVERIGHT) && (oldinput & BT_MOVERIGHT);

            bool lean_left = owner.CheckInventory('BT_LeanLeft', 1);
            bool lean_right = owner.CheckInventory('BT_LeanRight', 1);

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
                owner.speed = 0.5;
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

            PlayerPawn player = PlayerPawn(owner);

            if (blocked)
            {
                RestoreLeanBodyDefaults(player, pi);
                leantilt *= 0.82;
                leanlerp += (leantilt - leanlerp) * 0.14;
                if (abs(leanlerp) < 0.25)
                    leanlerp = 0;
                owner.A_SetRoll(leanlerp, SPF_INTERPOLATE);
            }
            else
            {
                double targetViewzOffset = map(
                    abs(leantilt),
                    0.0, 90.0,
                    0.0,
                    -player.viewheight * pi.CrouchFactor
                );
                pi.viewz += targetViewzOffset - lastViewzLeanOffset;
                lastViewzLeanOffset = targetViewzOffset;

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
                    double(player.radius) / player.FullHeight
                );

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

                leanlerp += (leantilt - leanlerp) * 0.16;
                owner.A_SetRoll(leanlerp, SPF_INTERPOLATE);
            }
        }
    }
}
