# Context for this fork (GotTheShakes/Moonfin-Core)

Personal fork of Moonfin-Core (Flutter media client). Work goes on the branch
`aether-atmos-dv`; do not touch the upstream release flow. The owner plays Plex
on a MacBook Pro (OLED) running macOS 27.3 beta, listens on AirPods Max with
Spatial Audio, and installs the DMG this fork builds over the official app
(same bundle id, `org.moonfin.app`). They are not a developer: explain in plain
words and give exact steps.

## How to build and ship (no local Xcode/Flutter needed)

The macOS job in `.github/workflows/build.yml` builds an ad-hoc signed DMG:

    gh workflow run build.yml -R GotTheShakes/Moonfin-Core --ref aether-atmos-dv \
      -f run_all=false -f macos=true

Then watch the run, and download the `macos-dmg` artifact from the run's page.
CI pins Xcode 26.3 and the Flutter version in the workflow. Aether itself
prefers Xcode 27, so a toolchain error is possible. A green build only proves it
compiles. Audio and picture quality can only be judged by the owner, by ear and
eye.

On a fresh clone of the fork, remote-tracking refs may be missing, so run
`git fetch origin +refs/heads/aether-atmos-dv:refs/remotes/origin/aether-atmos-dv`
after pushing if a hook complains about unpushed commits.

## Done so far (see docs/macos-atmos-and-dolby-vision.md)

1. **Atmos / DTS:X heights on macOS.** AetherEngine's `TrueHDObjectAudio` and
   `DTSXObjectAudio` package traits are written into
   `macos/Runner.xcodeproj/project.pbxproj` and re-written after the project is
   saved by `macos/scripts/wire_macos_player.rb` (the `xcodeproj` gem drops the
   `traits` key). With the setting on, `LoadOptions.objectAudioRendering` is
   `.render(.l916)`.
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
