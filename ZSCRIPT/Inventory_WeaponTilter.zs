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

class WeaponTilterInventory : Inventory
{
	double currentRoll, crABS, aVelocity, playerVel, adjustedCrABS;
	float rResistance, rVelocity, rLimit, rWallLoweringAmount;
	vector2 direction, velocityUnit;
	int currentTickCount;
	bool limit, offset, lowering, wallDetection;
	double loweringAmount, loweringSmoothing;
	double duckAmount; // For wall detection lowering
	
	// Weapon exclusion arrays
	static const string NO_ROTATE[] =
	{
		"PB_Minigun",
		"PB_CryoRifle"
	};

	static const string SCOPED[] =
	{
		"PB_Railgun"
	};
	
	default
	{
		Inventory.MaxAmount 1;
	}
	
	// Helper function to check if weapon should skip rotation
	private bool SkipRotation()
	{
		let weap = owner.player.readyWeapon;
		if (!weap) return true;
		Name cls = weap.GetClassName();
		for (int i = 0; i < NO_ROTATE.Size(); i++)
			if (cls == NO_ROTATE[i]) return true;
		return false;
	}
	
	// Helper function to check if weapon is scoped
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
	
	// Wall detection function
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
	
	override void DoEffect()
	{
		super.DoEffect();
		
		currentTickCount++;
		
		// do nothing if the owner is null or not a player:
		if(!owner || !owner.player)
			return;
			
		let weaponsprite = owner.player.FindPSprite(PSP_WEAPON);
		
		if(!(owner.player.weaponstate & wf_weaponbobbing))
			return;

		if(weaponsprite)
		{
			// Check if we should skip rotation entirely (like for minigun/cryorifle)
			if (SkipRotation())
			{
				// Reset any applied effects and return
				weaponsprite.rotation = 0;
				if(offset)
				{
					// Reset any offset modifications
					weaponsprite.y = weaponsprite.y - loweringAmount;
				}
				return;
			}
			
			// Check if scoped (railgun specific handling)
			if (IsScoped())
			{
				// No tilt or offset when scoped
				weaponsprite.rotation = 0;
				if(offset)
				{
					weaponsprite.y = weaponsprite.y - loweringAmount;
				}
				return;
			}
			
			//get cvars, optimized with tick count
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
			
			//calculate tilt
			aVelocity = atan2(owner.vel.y, owner.vel.x);
			direction = (sin(-owner.angle), cos(-owner.angle));
			velocityUnit = owner.vel.xy;
			currentRoll += (velocityUnit dot direction) * rVelocity;
			currentRoll *= rResistance;
			crABS = abs(currentRoll);
			
			// Handle weapon lowering based on movement
			if(lowering)
			{
				// Calculate lowering amount based on sideways movement
				double sidewaysMovement = abs(owner.player.cmd.sidemove);
				double targetLowering = 0;
				
				// Apply lowering when strafing
				if(sidewaysMovement > 0)
				{
					// More movement = more lowering, scaled by velocity
					targetLowering = min(22.0, (owner.vel.length() * 1.5) + sidewaysMovement * 0.05);
				}
				
				// Handle wall detection lowering
				if(wallDetection && bFacingWall())
				{
					// Increase target lowering when facing a wall
					targetLowering = min(30.0, targetLowering + rWallLoweringAmount);
					
					// Alternative: Use a duck-like system that builds up over time
					duckAmount = clamp(duckAmount + 6, 0, 30);
					targetLowering = max(targetLowering, duckAmount);
				}
				else
				{
					// Gradually reduce duck amount when not facing walls
					duckAmount *= 0.9;
				}
				
				// Smooth the lowering effect (recenter speed)
				loweringSmoothing = 0.2;
				loweringAmount += (targetLowering - loweringAmount) * loweringSmoothing;
				
				// Apply the lowering offset
				if(offset)
				{
					adjustedCrABS = weaponsprite.y + crABS + loweringAmount;
					weaponsprite.y = adjustedCrABS;
				}
				else
				{
					weaponsprite.y = weaponsprite.y + loweringAmount;
				}
			}
			else if(offset)
			{
				// Original offset behavior
				adjustedCrABS = weaponsprite.y + crABS;
				weaponsprite.y = adjustedCrABS;
			}
			
			//roll cap
			if(limit)
			{
				if(currentRoll > rLimit)
				{
					currentRoll = rLimit;
				}
			}
			
			//apply tilt
			weaponsprite.rotation = currentRoll;
		}
	}
}