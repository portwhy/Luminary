# Luminary

A native macOS app for watching your [Jellyfin](https://jellyfin.org) library. It's built to feel smooth: 120 Hz
scrolling, instant window resizing, and mpv playback with hardware decoding, so almost every file plays directly
without the server transcoding it.

Luminary is free, open source, and not affiliated with the Jellyfin project.

> **Built with AI.** I designed and tested Luminary, and the code was written by Claude (Anthropic's AI) under my
> direction. I use it every day on my own devices. Bug reports are very welcome.

## Features

- Home with Continue Watching, Next Up and Recently Added shelves, plus your libraries, favorites and search
- Filter libraries by genre, tag and year
- Movie and series pages with cast, ratings, episode thumbnails, trailers and IMDb / TMDB links
- Right-click menus: mark watched, favorite, remove from Continue Watching, go to series or season
- mpv player: direct play first, with transcoding at the quality you pick when needed
- Audio and subtitle tracks with Jellyfin's labels and defaults, subtitle timing and size, ASS styling
- Skip Intro / Credits (Jellyfin 10.10+ with a segment plugin such as Intro Skipper), chapters, Up Next autoplay
- Media keys and AirPods controls, playback stats panel, trackpad scrubbing
- Optional glass window background (View → Glass Background, ⌃⌘G)
- Interface size from 85 % to 150 % (⌘= / ⌘-), and settings for quality at home vs away, skipping intros and
  credits, autoplay, preferred audio and subtitle languages, subtitle look, HDR and more
- Every shortcut can be rebound in Settings

## What it direct plays

Luminary plays the original file whenever it can, so the server doesn't have to transcode. mpv (with FFmpeg)
handles almost any format, and Luminary tells Jellyfin so.

| | Direct play |
|---|---|
| **Containers** | MKV, MP4, M4V, MOV, WebM, AVI, TS / M2TS / MTS, WMV / ASF, FLV, 3GP, OGV / OGG, MPG / MPEG, VOB, DivX / Xvid |
| **Video codecs** | Anything FFmpeg decodes: H.264, HEVC / H.265 (8 and 10-bit), AV1, VP9, VP8, MPEG-2, MPEG-4, VC-1 and more. Hardware decoding through VideoToolbox where the Mac supports it (AV1 needs an M3 or newer, otherwise it's decoded in software). |
| **HDR** | HDR10 and HLG |
| **Audio** | Anything FFmpeg decodes, including AAC, AC3, E-AC3, TrueHD, DTS / DTS-HD, FLAC, Opus. Decoded on the Mac (no passthrough to a receiver). |
| **Subtitles** | Text: ASS / SSA (full styling and positioning), SRT, WebVTT, TTML, MOV text, SMI. Image: PGS, VobSub / DVD, DVB. Embedded or as separate files. |

The server only transcodes when you pick a lower quality yourself. In that case audio and text subtitles can
still be switched, and image subtitles are burned in.

## Requirements

- A Mac with Apple Silicon (M1 or newer)
- macOS 14 Sonoma or newer (developed on macOS 26)
- A Jellyfin server, version **10.9 or newer**

## Install

1. Download `Luminary-x.y.z.dmg` from the [Releases](../../releases) page and open it.
2. Drag **Luminary** onto the **Applications** shortcut next to it.
3. Open it. macOS will say it can't verify the developer, because the app isn't signed with a paid Apple
   developer account. To allow it:
   - Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the Luminary
     message. Then confirm.
   - Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Luminary.app`

   You only need to do this once per version.
4. Sign in with your server address: a LAN IP address (Luminary tries `http://…:8096` first), a
   hostname (`https://` first), or a full URL with a base path such as `https://media.example.com/jellyfin`.

macOS may ask whether Luminary can use your login Keychain, where it keeps your sign-in. Choose **Always Allow**.

**Updates:** from 0.2.0 on, Luminary updates itself. It checks about once a day (or use **Luminary → Check for
Updates…**), and you can turn on automatic installs in **Settings → General**. Updates are signed, and the app
refuses any that aren't.

## Shortcuts

All shortcuts are listed, and can be rebound, in **Luminary → Settings… (⌘,) → Shortcuts**. Defaults:

| Player | | Library | |
|---|---|---|---|
| Space · click | Play / pause | ⌘[ · mouse back button | Back |
| ← / → (⇧ for 30 s) | Seek 5 s (lengths adjustable in Settings) | ⌘1 / ⌘2 / ⌘3 | Home / Next Up / Favorites |
| Return | Skip intro / credits, or play next | ⌘4 – ⌘9 | Libraries in sidebar order |
| Page Up / Page Down | Previous / next chapter | ⌘F | Search |
| P / N | Previous / next episode | ⌘R | Refresh |
| ↑ / ↓ · M | Volume · mute | ⌃⌘S | Show / hide sidebar |
| A / S | Next audio / subtitle track | ⌃⌘G | Glass background |
| Z / X | Subtitles earlier / later | ⌘= / ⌘- / ⌘0 | Bigger / smaller / actual size |
| [ / ] / \\ | Slower / faster / normal speed | | |
| F · double-click | Full screen | | |
| Esc | Exit full screen, then back to library | | |
| I | Playback stats | | |
| 0 – 9 | Jump to 0–90 % | | |
| ⌘Z | Jump back to where you were (after a big jump) | | |
| Two-finger swipe | Scrub | | |

**Quality:** ⚙︎ → Quality. "Original" direct-plays the file. Picking a lower bitrate makes the server transcode
(HLS fMP4, HEVC or H.264). Audio and text subtitles can still be switched while transcoding. Image subtitles (PGS)
are burned in.

## Build from source

The Xcode Command Line Tools are enough (`xcode-select --install`).

```bash
git clone <this repo>
cd Luminary
./scripts/make-app.sh             # release build, installs ~/Applications/Luminary.app
./scripts/make-app.sh --package   # dist/Luminary-<version>.dmg for a release
./scripts/dev.sh                  # optimized build that runs straight from the terminal
./scripts/release.sh              # publish a release (DMG + GitHub release + update feed)
```

`swift test` runs the JellyfinKit unit tests (no server needed). It needs the full Xcode, for XCTest.

## How it's built

```
Sources/
├── JellyfinKit/      UI-free Jellyfin API client: sign-in, libraries, items, playback negotiation, images
└── Luminary/
    ├── Player/       libmpv (MPVKit) player, overlay controls, reporting, Now Playing
    ├── Views/        library window, home, grids, detail pages, filters, login
    ├── Session/      sign-in state and navigation
    ├── Images/       cached, downsampled image pipeline
    ├── Hotkeys/      rebindable shortcuts
    └── Settings/
Tests/JellyfinKitTests/
```

- **Rendering:** mpv's `gpu-next` → Vulkan → MoltenVK → Metal, into a `CAMetalLayer`. **Decoding:** VideoToolbox.
  **Subtitles:** libass.
- **Direct play first:** Luminary sends Jellyfin a device profile and plays the original file whenever it can.
- **Reporting:** playback start, progress every 10 s and stop are reported to the server, so resume points and
  watched state stay in sync with your other Jellyfin apps.
- **Sign-in:** the token is sent in the `Authorization` header and stored in the Keychain.

## License

Luminary is licensed under the [GNU General Public License v3](LICENSE). It uses
[MPVKit](https://github.com/mpvkit/MPVKit), which bundles [mpv](https://mpv.io), [FFmpeg](https://ffmpeg.org),
libass, libplacebo and MoltenVK under their own licenses. Its GPL build is used, which is why Luminary is GPL too.
In-app updates use [Sparkle](https://sparkle-project.org) (MIT license).
