# Universal Weapon Lowering, Wall Detection & Rotational Tilting

An experimental fork of https://github.com/generic-name-guy/universal-weapon-tilt-gz by Generic Name Guy.
This branch adds code made by Dithered Output, maker of Siren, that adds Weapon Lowering when tilting and Wall Detection.
----------------------------

If your addon has a weapon that has too many overlays and doesn't play nice with this Universal Tilter, you can edit the Zscript file Inventory_WeaponTilter.zs and add your own exceptions:

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
