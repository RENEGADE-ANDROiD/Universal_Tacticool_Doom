/*
Part of Universal Weapon Tilter by generic name guy.
*/

class WeaponTilterEventHandler : EventHandler
{
	bool bdFamilyDetected;
	bool bdFamilyProbed;

	static const Name BD_FAMILY_MARKERS[] =
	{
		'SwitchableWeapon', 'BrutalMapEnhancer', 'PB_Minigun', 'PB_Railgun',
		'BDPBattleRifle', 'PBWP_CA_WeaponBase', 'GoFatality', 'ExecutionToken',
		'BDV21Axe', 'BrutalBlood', 'PB_Berserk'
	};

	void ProbeBDFamily()
	{
		if (bdFamilyProbed)
			return;

		bdFamilyProbed = true;
		bdFamilyDetected = false;

		for (int i = 0; i < BD_FAMILY_MARKERS.Size(); i++)
		{
			if (Object.FindClass(BD_FAMILY_MARKERS[i]))
			{
				bdFamilyDetected = true;
				return;
			}
		}
	}

	bool IsBDFamilyDetected()
	{
		ProbeBDFamily();
		return bdFamilyDetected;
	}

	private void GiveTilter(PlayerPawn mo)
	{
		if (mo && mo.player && !mo.FindInventory("WeaponTilterInventory"))
			mo.A_GiveInventory("WeaponTilterInventory", 1);
	}

	override void PlayerEntered(PlayerEvent e)
	{
		GiveTilter(players[e.PlayerNumber].mo);
	}

	override void PlayerRespawned(PlayerEvent e)
	{
		GiveTilter(players[e.PlayerNumber].mo);
	}

	override void WorldLoaded(WorldEvent e)
	{
		ProbeBDFamily();

		for (int i = 0; i < MAXPLAYERS; i++)
		{
			if (!playerInGame[i] || !players[i].mo)
				continue;
			GiveTilter(players[i].mo);
		}
	}

	override void WorldTick()
	{
		for (int i = 0; i < MAXPLAYERS; i++)
		{
			if (!playerInGame[i] || !players[i].mo || !players[i].mo.player)
				continue;

			GiveTilter(players[i].mo);

			let inv = WeaponTilterInventory(players[i].mo.FindInventory("WeaponTilterInventory"));
			if (inv)
				inv.ApplyPose(players[i]);
		}
	}
}
