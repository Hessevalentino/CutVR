<p align="center">
  <img src="docs/icon.png" width="128" alt="CutVR icon">
</p>

<h1 align="center">CutVR</h1>

<p align="center">
  <b>Cut VR video in seconds. No re-encoding. No lost headset metadata.</b><br>
  A tiny, fast, native macOS editor for 180° / 360° and stereoscopic VR video.
</p>

<p align="center">
  <img src="docs/preview.jpg" width="100%" alt="CutVR – lossless VR video editing">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/SwiftUI-native-0D96F6?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/powered%20by-FFmpeg-007808?logo=ffmpeg&logoColor=white" alt="FFmpeg">
  <img src="https://img.shields.io/badge/ExifTool-metadata-555555" alt="ExifTool">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/lossless-stream%20copy-2ea44f" alt="Lossless stream copy">
  <img src="https://img.shields.io/badge/VR180-%E2%9C%93-6f42c1" alt="VR180">
  <img src="https://img.shields.io/badge/VR360-%E2%9C%93-6f42c1" alt="VR360">
  <img src="https://img.shields.io/badge/stereo-SBS%20%7C%20TB-6f42c1" alt="Stereo SBS / TB">
  <img src="https://img.shields.io/badge/8K-ready-6f42c1" alt="8K ready">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Meta%20Quest-0467DF?logo=meta&logoColor=white" alt="Meta Quest">
  <img src="https://img.shields.io/badge/Apple%20Vision%20Pro-000000?logo=apple&logoColor=white" alt="Apple Vision Pro">
  <img src="https://img.shields.io/badge/Pico-1A1A1A" alt="Pico">
  <img src="https://img.shields.io/badge/PlayStation%20VR2-003791?logo=playstation&logoColor=white" alt="PlayStation VR2">
  <img src="https://img.shields.io/badge/Valve%20Index-171A21?logo=valve&logoColor=white" alt="Valve Index">
  <img src="https://img.shields.io/badge/HTC%20Vive-00B2E3" alt="HTC Vive">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/DeoVR-player-FF6A00" alt="DeoVR">
  <img src="https://img.shields.io/badge/HereSphere-player-FF6A00" alt="HereSphere">
  <img src="https://img.shields.io/badge/Skybox-player-FF6A00" alt="Skybox">
  <img src="https://img.shields.io/badge/YouTube%20VR-FF0000?logo=youtube&logoColor=white" alt="YouTube VR">
</p>

---

## Why CutVR?

You shot an 8K VR video. You only want to trim the start and cut out a few dull minutes.
Most editors make you **re-render the whole thing**. That takes hours and costs quality.
Then the headset shows the video **flat and doubled**, because the editor dropped the VR metadata.

CutVR fixes both:

- ⚡ **Instant.** Exports run at disk speed. Cutting 30 seconds from a 13 GB 8K file takes about **1.5 s**. Joining four parts takes about **4.5 s**.
- 🎯 **Lossless.** Not a single frame is re-encoded. You get exactly the pixels you recorded.
- 🥽 **Headset-ready.** Projection, stereo layout and spherical tags come out **byte for byte** as they went in, and CutVR checks the result after every export.
- 🪶 **Dead simple.** Cut, delete, export. That's the whole workflow.

## How it works: three moves

| | |
|---|---|
| ✂️ **Cut** | Press **C** to cut at the playhead, or take the scissors (**B**) and click the timeline wherever you need a cut. |
| 🗑️ **Delete** | Click a clip with the select tool (**V**) and press **⌫**. The rest closes up and the timeline always shows the final video. |
| 📤 **Export** | Press **⌘S**. Done. You get one clean file with every VR parameter intact. |

Changed your mind? **⌘Z**.

## Features

- **Scissors and clip workflow.** Cut anywhere, delete any clip, and the remaining clips are joined automatically (ripple delete).
- **Live preview of the result.** Playback skips deleted parts, so you see exactly what you'll export.
- **Headset parameter overlay (H).** Resolution, frame rate, codec, bitrate, stereo layout, projection, file-name VR tags, and whether the headset will detect the format by itself.
- **VR metadata check.** A badge shows at a glance whether the file carries embedded VR metadata. After export, a ✓ confirms that nothing was lost.
- **Keyframe-accurate cuts.** Stream copy can only start a clip on a keyframe, so CutVR snaps every cut there and moves the playhead to it. What you see is what you get.
- **Smart file names.** Output is `EDIT_<original name>`, so tags like `_180_LR` or `_3dh` that players read from the name stay intact.
- **Dark, distraction-free UI** with drag & drop.
- **Scriptable.** Runs headless from the command line too.

## What metadata is preserved

| Standard | Boxes | Used by |
|---|---|---|
| Google Spherical Video V2 | `st3d`, `sv3d` (`proj`, `equi`, `cbmp`) | YouTube VR, Meta Quest players, Skybox, DeoVR, HereSphere |
| Google Spherical Video V1 | `uuid` (GSpherical XML) | Older players and cameras |
| Apple spatial / immersive | `vexu`, `hfov` | Apple Vision Pro |
| QuickTime user data | title, author, description, thumbnail | Finder, players, libraries |
| File-name tags | `_180`, `_360`, `_LR`, `_TB`, `_SBS`, `_3dh`, `_fisheye`… | DeoVR, HereSphere, Skybox, Pigasus… |

> **Why not just use FFmpeg?** Because `ffmpeg -c copy` alone silently breaks VR files. Into `.mov` it drops `st3d`/`sv3d` entirely. Into `.mp4` it adds a `vexu` box that overrides the stereo mode, so readers see it as "unspecified". The Google V1 tag is always lost. CutVR lets FFmpeg do the fast cutting, then writes the source's VR boxes back byte for byte.

## Download

1. Grab **CutVR.zip** from the [latest release](https://github.com/Hessevalentino/CutVR/releases/latest). It is a universal app for Apple Silicon and Intel.
2. Unzip it and drag **CutVR.app** to your Applications folder.
3. Install the two free helpers CutVR uses:

   ```sh
   brew install ffmpeg exiftool
   ```

4. **First launch:** the app is not notarized by Apple, so macOS will warn you. Right-click **CutVR.app → Open → Open**. You only need to do this once.
   If macOS still refuses, run `xattr -dr com.apple.quarantine /Applications/CutVR.app`.

Requires macOS 15 or newer.

## Build from source

```sh
git clone https://github.com/Hessevalentino/CutVR.git
cd CutVR
./build.sh            # → dist/CutVR.app
open dist/CutVR.app
```

Needs Xcode or the Command Line Tools (Swift 6), plus `brew install ffmpeg exiftool`. The build produces a universal binary.

## Keyboard shortcuts

| Key | Action |
|---|---|
| **V** / **B** | Select tool / scissors tool |
| **C** | Cut at the playhead |
| **⌫** | Delete the selected clip |
| **⌘Z** | Undo |
| **Space** | Play / pause |
| **←** / **→** | Previous / next frame |
| **H** | Toggle the headset parameter overlay |
| **⌘O** | Open video |
| **⌘S** | Export |

## Command line

```sh
dist/CutVR.app/Contents/MacOS/CutVR --cut <source> <dest> <start-end> [<start-end> …]

# keep 0–30 s and 120–150 s, joined into one file
dist/CutVR.app/Contents/MacOS/CutVR --cut in.mp4 out.mp4 0-30 120.02-150
```

Times are in seconds, and parts are joined in the given order.

## Under the hood

1. **Cut.** Each kept clip is extracted with `ffmpeg -ss … -t … -c copy`, with no decoding and no encoding.
2. **Join.** Multiple clips are joined with FFmpeg's concat demuxer. CutVR cuts each part separately first, because using concat's `inpoint`/`outpoint` directly on the source loses about 1 s of video per join on files interleaved in 1 s chunks.
3. **Restore VR boxes.** `VRBoxes.swift` parses the MP4/MOV box tree and replaces the output's VR boxes with exact copies from the source. Only the `moov` header is rewritten, and the media data is never touched.
4. **Restore user data.** ExifTool copies title, author, thumbnail and other tags.
5. **Verify.** The VR metadata of source and output are compared with both ffprobe and ExifTool, and the result is shown in the app.

## Good to know

- Cuts snap **back** to the nearest keyframe, usually less than 0.5 s away. That is the price of lossless editing.
- Exporting several clips needs free disk space for about **twice the result size** while it runs. Temporary parts sit next to the output and are deleted afterwards.
- Best results with `.mp4` and `.mov`. Other containers are cut losslessly too, but the VR box restoration step only applies to MP4/MOV.
- If your source has **no embedded VR metadata**, CutVR keeps the file name (and its VR tags). The overlay tells you how the headset will detect the format.

## Project layout

```
Sources/CutVR/
  App.swift           app entry, About panel, command-line mode
  EditorModel.swift   clips, cutting, playback mapping, export
  Views.swift         main window
  TimelineView.swift  clip timeline with scissors tool
  PreviewViews.swift  video preview and headset overlay
  Tools.swift         ffmpeg/exiftool runner, VR probe, exporter
  VRBoxes.swift       byte-exact MP4/MOV VR box transfer
Icon/make_icon.swift  generates the app icon
build.sh              builds dist/CutVR.app
```

## License

[MIT](LICENSE) © Valentino Hesse

<p align="center">
  Made by <a href="https://hesse.works"><b>hesse.works</b></a>
</p>
