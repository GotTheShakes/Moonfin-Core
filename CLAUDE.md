# Context for this fork (GotTheShakes/Moonfin-Core)

Personal fork of Moonfin-Core (Flutter media client). Work goes on the branch
`aether-fel`, which builds the owner's DMG directly (no PRs; the owner asked
for none). `aether-atmos-dv` is the older branch it grew from and is not kept
up to date. Do not touch the upstream release flow. The owner plays Plex
on a MacBook Pro (OLED) running macOS 27.3 beta, listens on AirPods Max with
Spatial Audio, and installs the DMG this fork builds over the official app
(same bundle id, `org.moonfin.app`). They are not a developer: explain in plain
words and give exact steps.

## How to build and ship (no local Xcode/Flutter needed)

The macOS job in `.github/workflows/build.yml` builds an ad-hoc signed DMG:

    gh workflow run build.yml -R GotTheShakes/Moonfin-Core --ref aether-fel \
      -f run_all=false -f macos=true

Then watch the run, and download the `macos-dmg` artifact from the run's page.
CI pins Xcode 26.3 and the Flutter version in the workflow. Aether itself
prefers Xcode 27, so a toolchain error is possible. A green build only proves it
compiles. Audio and picture quality can only be judged by the owner, by ear and
eye.

On a fresh clone of the fork, remote-tracking refs may be missing, so run
`git fetch origin +refs/heads/aether-fel:refs/remotes/origin/aether-fel`
after pushing if a hook complains about unpushed commits.

## Pulling in upstream Moonfin

1. The owner clicks **Sync fork** on the fork's `main` on GitHub (main carries
   no fork work).
2. Merge `origin/main` into the working branch, resolve conflicts, push, and
   run the macOS build.
3. **Engine bumps:** upstream pins AetherEngine as a remote package reference
   in `macos/Runner.xcodeproj/project.pbxproj` and in
   `macos/scripts/wire_macos_player.rb` (`aether_remote_url`,
   `aether_revision`). This fork removes that reference and links the engine
   only through `macos/AetherEngineTraits/Package.swift`. If a merge brings a
   new revision, put it in that Package.swift (and the script), and drop the
   re-added remote reference from the .pbxproj, or the build stays on the old
   engine or fails to resolve. Check that the traits still compile.

## Done so far (see docs/macos-atmos-and-dolby-vision.md)

1. **Atmos / DTS:X heights on macOS.** With the setting on,
   `LoadOptions.objectAudioRendering` is `.render(.l916)`. The engine traits
   (`TrueHDObjectAudio`, `DualLayerDolbyVision`; `DTSXObjectAudio` is left out
   because it fails to compile under Xcode 26.3, run 42526273238) are set in
   the local package `macos/AetherEngineTraits`, which pins the engine revision
   and is the Runner target's ONLY link to the engine (it re-exports
   `AetherEngine`). Keeping a direct remote AetherEngine reference beside it
   made package resolution fail (run 42525399618, "binary target ... could not
   be mapped to an artifact"). `wire_macos_player.rb` removes a direct
   reference and adds the package; the revision now lives in its Package.swift. Builds before
   that package (up to run 42518227984) had NO traits: Xcode 26.3 ignores a
   `traits` list on a `.pbxproj` package reference, and LibTrueHD was absent
   from `Package.resolved`. The FEL log said `built without the
   DualLayerDolbyVision trait`. So heights were never actually on before it.
   Each macOS load logs `optional components built in: ...=true/false`.
2. **Dolby Vision composition.** Sets `forceDolbyVisionOnNonDVDisplay`, the same
   switch AetherPlayer uses. No Mac reports a Dolby Vision display, so Profile
   8.1 otherwise plays as its HDR10 base layer.
3. **Two settings (macOS only, shown only when `PlatformDetection.isMacOS`):**
   `UserPreferences.aetherHeightChannels` (default on, Settings, Playback,
   Audio) and `UserPreferences.aetherComposeDolbyVision` (default off,
   Settings, Playback, Player). Flutter passes them as `heightChannels` and
   `composeDolbyVision` in `lib/playback/aether_backend.dart`;
   `AetherVideoChannel.swift` parses them; `AetherPlayerWrapper.swift` applies
   them inside `#if os(macOS)` where `LoadOptions` is built. The explainer
   strings are English only (`lib/l10n/app_en.arb`).
4. **Plex library visibility bug** (Live TV toggle did not persist).
   `PlexUsersApi.updateUserConfiguration` was empty. It now keeps the
   configuration on the device through a `PlexConfigStore` (SharedPreferences
   backed, `_PlexPreferencesStore` in `lib/data/services/media_server_client_factory.dart`),
   keyed per server machine id and account. Unit tests are in
   `packages/server_plex/test/plex_items_api_test.dart`. Not yet confirmed by
   the owner on a real build; the run triggered after commit 4a60f06 is the first
   one that includes it.

## Open items

- **FEL A/B key (macOS):** pressing **E** during playback flips
  `AetherEngine.felResidualEnabled` (SPI `Diagnostics`, via
  `toggleFelResidual` on the `moonfin/ios_aether_control` channel, handled
  synchronously in `AetherVideoChannel.swift`) and shows a snackbar with the
  new state. Off composes each frame without the enhancement layer's residual
  (what MEL decodes to). Process-wide; reset to on at every `setSource`. Only
  has an effect on the FEL dual-layer route. Needs the DualLayerDolbyVision
  trait, so an `AETHER_LOCAL=1` build without it will not compile.
- **Back arrow left a black screen until Escape** (upstream bug, fixed on
  `aether-fel`, not yet confirmed by the owner). `_exitPlayback` pops through
  `runAfterBackKeyUp`, which waits for a back key's key up when
  `HardwareKeyboard` thinks one is pressed. On macOS that state can be stale
  (an Escape whose key up the system consumed), so a mouse click on the back
  arrow waited forever. The on-screen back button now passes
  `waitForBackKeyUp: false`. Worth reporting upstream.

- **Confirmed by the owner (run 42527709861, branch `aether-fel`):** the log
  showed `optional components built in: TrueHDObjectAudio=true
  DTSXObjectAudio=false DualLayerDolbyVision=true` and, on a Profile 7 FEL
  title, `DV P7 dual-layer route: taken (el_type=FEL, 3840x2160@23.976, budget
  80%)`. Picture, smoothness and audible heights not yet judged.
  **Runtime proof (2026-11-09, same build, TrueHD Atmos FEL title):**
  `FEL stream detected; engaging enhancement decoder`, `secondary decoder
  initialized for the enhancement layer`, `totals: composed=` rising ~25/s
  with every `bypass*` at 0 (no fallback frames). Audio: `[SpatialAudioBridge]
  init: layout=9.1.6 format=lpcm ... codecs=ipcm`, `TrueHD Atmos rendered into
  9.1.6 as PCM for the renderer`, `object configuration: LFE + 11 objects`,
  `bed levels` with `2 elevated` objects and Ltm/Rtm at about -33 dBFS RMS
  (peaks -6), so height content reaches the bed handed to macOS. Not provable
  from the app: macOS spatialising the 16-channel PCM on AirPods (the engine
  docs measured it on a MacBook Air, macOS 27). The owner does
  not care about DTS:X heights, so the Xcode 27 experiment to restore
  `DTSXObjectAudio` is dropped. The height setting is now titled for TrueHD
  Atmos only.
- **FEL / dual-layer Dolby Vision** (branch `aether-fel`, off `aether-atmos-dv`).
  Adds the `DualLayerDolbyVision` trait and a default-off macOS setting,
  `UserPreferences.aetherDualLayerDolbyVision` ("Play Dolby Vision FEL layers",
  below Compose), passed as `dualLayerDolbyVision` and applied as
  `LoadOptions.preferDualLayerDolbyVision`. Engine docs
  (`docs/dolby-vision-fel.md` at the pinned revision) say the composed picture is
  correct on macOS but that macOS applying the attached per-frame metadata is
  unmeasured (proven on tvOS only). The route runs on the software host; with
  `objectAudioRendering` set it keeps Atmos objects (verified on macOS). Confirm
  the route from the unified log (subsystem `de.superuser404.AetherEngine`, look
  for `DV P7 dual-layer route`). Needs the owner's judgement on a real file.
- The owner already confirmed (log) that Compose Dolby Vision engages on a
  Profile 7 file: `AE#455: serving HEVC DV Profile 7 (converted to 8.1) as
  Profile 5`. Plex direct played it. They saw no visible difference.
- **`DolbyVisionStillReshaping` trait.** AetherPlayer enables it, this fork does
  not. Find out what it changes before adding.
- Whether Plex direct plays TrueHD on macOS depends on Moonfin's Plex device
  profile (it advertises Dolby Vision and HDR only when `NSScreen` EDR headroom
  is above 1.0; see `AetherVideoChannel.swift`). A Plex transcode loses Dolby
  Vision and Atmos. Worth confirming from a playback log.
- Library order is now saved for Plex too, but `PlexUserViewsApi.getUserViews`
  does not apply `orderedViews`, so reordering still has no visible effect.
- Search-index entries for the two new settings
  (`lib/ui/screens/settings/panel/settings_search_index.dart`) and other
  languages' strings were not added.
- Heights have not been confirmed audible, and the picture with Compose on has
  not been judged, by the owner on a real file.

## Reference

- AetherPlayer (comparison app) sets, in `Sources/Shared/PlayerViewModel.swift`:
  `forceDolbyVisionOnNonDVDisplay`, `audioBridgeMode`, `objectAudioRendering`
  (`.render(.l916)`), and builds with traits
  `TrueHDObjectAudio, DTSXObjectAudio, DolbyVisionStillReshaping`.
- Object audio needs macOS 26 or later. Over AirPlay it is not lossless.
- Moonfin's macOS playback wrapper is shared with tvOS and iOS under
  `tvos/Runner/Playback/Aether/`; keep macOS-only changes inside `#if os(macOS)`.
- Flutter and Dart could not be run in the sandbox where the code was first
  written, so run `flutter analyze` and the package tests when possible.
