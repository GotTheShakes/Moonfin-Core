# macOS: Atmos height channels and Dolby Vision composition

This fork turns on two AetherEngine features that stock Moonfin leaves off on
macOS. Both are in Moonfin's playback settings and apply to the next file you
open.

## Where the settings are

| Setting | Location | Default |
| --- | --- | --- |
| Height channels from TrueHD and DTS:X | Settings, Playback, Audio, directly below "Downmix to Stereo" | On |
| Compose Dolby Vision on this display | Settings, Playback, Player (listed under the Video heading), in "Media Player Behavior" below the zoom mode | Off |
| Play Dolby Vision FEL layers | Same place, directly below "Compose Dolby Vision" | Off |

Both appear on macOS only.

## What they do

- **Height channels.** TrueHD Atmos and DTS:X tracks are rendered into a 9.1.6
  bed and handed to macOS as lossless PCM, which macOS plays as spatial audio.
  Needs macOS 26 or later. Over AirPlay the audio is not lossless.
  Tracks without objects play as before.
- **Compose Dolby Vision.** No Mac reports a Dolby Vision display, so Profile 8.1
  sources normally play as their HDR10 base layer. This hands composition to
  AVPlayer. Experimental. If the picture looks shifted or washed out, turn it
  off and reopen the file.
- **Play Dolby Vision FEL layers.** A Profile 7 FEL source normally loses its
  enhancement layer when it is converted to Profile 8.1. This decodes both
  layers in hardware and combines them on the GPU (the engine's
  `preferDualLayerDolbyVision`, built with the `DualLayerDolbyVision` trait).
  The engine documents the combined picture as correct on macOS; whether macOS
  then applies the attached per-frame Dolby Vision metadata is unmeasured.
  Experimental. A Profile 7 MEL file, or one too heavy to decode twice in real
  time, keeps the normal route.

## What was changed

- `macos/AetherEngineTraits/`: a small local Swift package that depends on the
  same AetherEngine revision with the `TrueHDObjectAudio` and
  `DualLayerDolbyVision` traits on. `DTSXObjectAudio` is left out for now: its
  decoder does not compile with Xcode 26.3, which CI uses, so DTS:X tracks play
  without their heights. It is the Runner target's only link to
  the engine (it re-exports `AetherEngine`), so the engine is built with them. Without them the object audio and FEL code is not
  compiled in. (A `traits` list on the package reference in the `.pbxproj` is
  ignored by Xcode 26, which CI uses, so the first builds had none of them.)
- `macos/scripts/wire_macos_player.rb`: adds that package and removes any direct
  AetherEngine reference, which next to it breaks package resolution.
- `lib/preference/user_preferences.dart`, `lib/playback/aether_backend.dart`,
  the two settings screens, and `app_en.arb`: the two preferences and tiles.
  Only the English strings are added.
- `tvos/Runner/Playback/Aether/AetherVideoChannel.swift` and
  `AetherPlayerWrapper.swift`: pass the preferences into the engine's
  `LoadOptions` (`objectAudioRendering`, `forceDolbyVisionOnNonDVDisplay`), on
  macOS only.

## Checking a build

Playing any file logs which components the build has:

    log stream --level debug --predicate 'subsystem == "de.superuser404.AetherEngine"' | grep -E "optional components|dual-layer|AE#455"

Look for `optional components built in: TrueHDObjectAudio=true DTSXObjectAudio=false DualLayerDolbyVision=true ...`.

## Limits

- Dolby Vision and Atmos only survive when Plex direct plays the file. A Plex
  transcode loses them.
- Whether the built-in MacBook speakers reproduce heights is unconfirmed.
  AirPods with Spatial Audio are the surest way to hear them.
