SoftReset::
	call StopAllSounds
	call GBPalWhiteOut
	ld c, 32
	call DelayFrames
	; fallthrough

Init::
;  Program init.
	di

	xor a
	ldh [rIF], a
	ldh [rIE], a
	ldh [rSCX], a
	ldh [rSCY], a
	ldh [rSB], a
	ldh [rSC], a
	ldh [rWX], a
	ldh [rWY], a
	ldh [rTMA], a
	ldh [rTAC], a
	ldh [rBGP], a
	ldh [rOBP0], a
	ldh [rOBP1], a

	ld a, LCDC_ON
	ldh [rLCDC], a
	call DisableLCD

	ld sp, wStack

	ld hl, STARTOF(WRAM0)
	ld bc, SIZEOF(WRAM0)
.loop
	ld [hl], 0
	inc hl
	dec bc
	ld a, b
	or c
	jr nz, .loop

	call ClearVram

	ld hl, STARTOF(HRAM)
	ld bc, SIZEOF(HRAM)
	call FillMemory

	call ClearSprites

	ld a, BANK(WriteDMACodeToHRAM)
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	call WriteDMACodeToHRAM

	xor a
	ldh [hTileAnimations], a
	ldh [rSTAT], a
	ldh [hSCX], a
	ldh [hSCY], a
	ldh [rIF], a
	ld a, IE_VBLANK | IE_TIMER | IE_SERIAL
	ldh [rIE], a

	ld a, 144 ; move the window off-screen
	ldh [hWY], a
	ldh [rWY], a
	ld a, 7
	ldh [rWX], a

	ld a, CONNECTION_NOT_ESTABLISHED
	ldh [hSerialConnectionStatus], a

	ld h, HIGH(vBGMap0)
	call ClearBgMap
	ld h, HIGH(vBGMap1)
	call ClearBgMap

	ld a, LCDC_DEFAULT
	ldh [rLCDC], a
	ld a, 16
	ldh [hSoftReset], a
	call StopAllSounds

	ei

	callfar BridgeCheck ; gen1-pvp Milestone 1 upstream patch
	; gen1-pvp Milestone 7 upstream patch: only proceed into team
	; building if the bridge actually came back OK -- a prior version
	; called TeamBuilderSpeciesPicker unconditionally here, so a player
	; would see BRIDGE ERROR flash and then land in team building
	; anyway, as if connected.
	ld a, [wBridgeCheckResult]
	and a
	jr z, .skipTeamBuilder
	; gen1-pvp upstream patch: MatchModeMenu/RealTeamBuilder/ThinBattle/
	; BattleChoiceScreen all draw via the normal PlaceString/hlcoord
	; convention, which only writes into wTileMap (WRAM) -- it reaches
	; real VRAM solely through AutoBgMapTransfer, run from the VBlank
	; handler and gated on hAutoBGTransferEnabled. That flag is off from
	; cold boot and this project's own code doesn't turn it on until
	; right before predef PlayIntro, below -- after every PvP screen has
	; already run. BridgeCheck's own "BRIDGE OK" screen only ever
	; appeared because it bypasses this pipeline and writes vBGMap0
	; directly (see its own comment); nothing after it did the same, so
	; every later PvP screen was invisible on real hardware/a real
	; window despite writing correct WRAM state -- exactly the class of
	; gap ADR-022 already named ("an event-stream test cannot verify
	; rendering"), just one level higher up than that ADR caught: every
	; existing test reads wTileMap directly rather than watching a real
	; screen, so this was never observable until a human ran a real SDL
	; window (interactive_client.c) and watched it stay on BRIDGE OK.
	; vBGMap0, not vBGMap1: a few lines above this hook, Init sets
	; hWY/rWY = 144 ("move the window off-screen"), so the window layer
	; (vBGMap1 -- what init.asm's own later, post-PvP-flow setup uses,
	; once something has moved the window back on screen) isn't visible
	; yet here. Only the background layer is, which is also exactly
	; where BridgeCheck writes "BRIDGE OK" directly.
	; gen1-pvp upstream patch: enables the background WRAM(wTileMap)->VRAM
	; transfer for the whole PvP flow -- see this comment's own earlier
	; history for why (every PvP screen's rendering, not just the ones
	; with their own ForceMenuSync, depends on this: ThinBattleRun's HP
	; bars/move text/SEND_OUT all draw via the same wTileMap convention
	; and have no explicit sync of their own). A same-destination race
	; between this and rom/pvp/*.asm's own explicit ForceMenuSync calls
	; was found (a real, human-visible torn cursor frame) and "fixed" by
	; disabling this entirely -- which broke battle rendering outright,
	; since it's the *only* thing that ever flushes everything this flag
	; doesn't explicitly cover. Reverted: each ForceMenuSync now brackets
	; its own copy with a local disable/restore of this flag instead (see
	; any of their own comments), so the two mechanisms take turns
	; owning the destination rather than one being switched off for good.
	ld a, HIGH(vBGMap0)
	ldh [hAutoBGTransferDest + 1], a
	xor a
	ldh [hAutoBGTransferDest], a
	ld a, 1
	ldh [hAutoBGTransferEnabled], a
	; gen1-pvp Milestone 7 upstream patch (ADR-012): try to pair with an
	; opponent before letting the player pick anything, so a species
	; selection has somewhere real to relay to (ADR-011). Deliberately
	; not gated on the outcome, though: MatchModeMenu's own bounded
	; retry budget means "no match found" is an ordinary result, not a
	; bridge failure, and every prior single-ROM-instance test (client/
	; tests/team_builder_test.c, client/online-bridge/online_bridge_
	; integration_test.c, client/tests/species_relay_test.c) exercises
	; the species picker without a second live opponent to pair with --
	; skipping the picker on "no match" would break all of them for no
	; behavioral gain, since selecting a species with no match to relay
	; to is exactly ADR-010's original, still-valid standalone case.
	callfar MatchModeMenu
	callfar TeamBuilderSpeciesPicker
.skipTeamBuilder

	predef LoadSGB

	ld a, BANK(SFX_Shooting_Star)
	ld [wAudioROMBank], a
	ld [wAudioSavedROMBank], a
	ld a, HIGH(vBGMap1)
	ldh [hAutoBGTransferDest + 1], a
	xor a
	ldh [hAutoBGTransferDest], a
	dec a
	ld [wUpdateSpritesEnabled], a

	predef PlayIntro

	call DisableLCD
	call ClearVram
	call GBPalNormal
	call ClearSprites
	ld a, LCDC_DEFAULT
	ldh [rLCDC], a

	jp PrepareTitleScreen

ClearVram::
	ld hl, STARTOF(VRAM)
	ld bc, SIZEOF(VRAM)
	xor a
	jp FillMemory


StopAllSounds::
	ld a, BANK("Audio Engine 1")
	ld [wAudioROMBank], a
	ld [wAudioSavedROMBank], a
	xor a
	ld [wAudioFadeOutControl], a
	ld [wNewSoundID], a
	ld [wLastMusicSoundID], a
	dec a
	jp PlaySound
