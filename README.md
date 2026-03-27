# Universal Weapon Lowering, Wall Detection & Rotational Tilting

An experimental fork of https://github.com/generic-name-guy/universal-weapon-tilt-gz by Generic Name Guy.
This branch adds code made by Dithered Output, maker of Siren, that adds Weapon Lowering when tilting and Wall Detection.  Also included is a trimmed down version of Immerse Lean (excluding Tilt++ and Universal Weapon Sway, as those are commonly found in many mods already) that includes modified version of the lean keybinds that allow you to move slowly while peeking around corners.  Lean code written by Joshua Hard (josh771).

Includes a customized menu with slider options for everything.
See Control Options to set Lean Keybind

Works universally for Doom, Doom II, Hexen, etc.
----------------------------

If your addon has a weapon that has too many overlays and doesn't play nice with this Universal Tilter, you can edit the Zscript file Inventory_WeaponTilter.zs and add your own exceptions:

	// Weapon exclusion arrays
	static const string NO_ROTATE[] =
	{
		"PB_Minigun", "PB_CryoRifle", "PB_NukageBarrel"
	};

	static const string SCOPED[] =
	{
		"PB_Railgun", "BDPBattleRifle", "PB_CSSG"
	};
