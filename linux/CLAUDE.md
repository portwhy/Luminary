# Luminary for Linux: plan and notes for Claude

The Mac app (repo root, Swift) is the reference: same name, same look and feel, same features. Its interface
code (SwiftUI/AppKit) can't run on Linux, so this is a separate native app in this folder. Read the Mac sources
for behaviour and Jellyfin details; don't port them line by line.

## The owner's priorities
- **Smooth and reliable, always.** Never trade that for features or looks. Never block the UI thread: network,
  image decoding and mpv commands all happen off it. Keep scrolling at the display's full refresh rate.
- Native look on Pop!_OS and GNOME, and works on every distro.
- Explain things plainly. Ask before big visual redesigns.

## Stack (decided)
- **Rust** + **GTK4 / libadwaita** (gtk4-rs, libadwaita-rs) for the UI. Native on GNOME and fine on COSMIC.
- **libmpv** for playback, rendered into the GTK window through mpv's render API (OpenGL, e.g. a `GtkGLArea`).
  Hardware decoding: `hwdec=auto-safe` (VA-API on AMD/Intel, NVDEC on NVIDIA).
- HTTP: `reqwest` (async, on a tokio runtime off the UI thread) + `serde` for Jellyfin's PascalCase JSON.
  Decode unknown enum strings leniently, so a new server value never breaks a whole page.
- Sign-in token stored in the desktop keyring through the Secret Service (libsecret / `oo7`), not a plain file.
- **Distribution: a Flatpak** (manifest in this folder, later published on Flathub). That covers Pop!_OS, Ubuntu,
  Fedora, Arch, Mint and Steam Deck in one package. App ID, something like `io.github.portwhy.Luminary`.
- Licence: GPLv3, same as the repo (mpv/FFmpeg).

## First session checklist (ask the owner)
1. Pop!_OS version and desktop (24.04 with COSMIC, or 22.04 with GNOME)?
2. GPU (NVIDIA / AMD / Intel)? This decides hardware decoding and what to test.
3. Monitor refresh rate (for the smoothness target).
Then install: rustup, the GTK4 + libadwaita dev packages, libmpv dev package, flatpak-builder.

## Milestones (each one usable and shown to the owner before the next)
1. **Skeleton:** a libadwaita window with the Luminary icon, the sign-in screen (server address, username,
   password), and a session that survives restarts. Server address handling as on Mac: a LAN IP tries
   `http://…:8096` first, a hostname tries `https://` first, full URLs with base paths work.
2. **Browsing:** sidebar (Home, Next Up, Favorites, libraries), Home shelves (Continue Watching, Next Up,
   Recently Added per library), library grids, search. An image cache (memory + disk, downsampled off the UI
   thread, shared in-flight requests) is part of this milestone, not later.
3. **Detail pages:** movie and series pages (backdrop fading into the background, overview, cast, ratings,
   seasons, episodes with thumbnails), right-click actions (watched, favourite, remove from Continue Watching).
4. **Player:** direct play first, transcode when needed, audio/subtitle tracks with Jellyfin labels and defaults,
   seek bar, resume, progress reporting, Skip Intro, Up Next, the keyboard shortcuts from the Mac README.
5. **Release:** library filters, settings, polish, then the Flatpak and a GitHub release.

## Jellyfin details already worked out on the Mac (see `../Sources/JellyfinKit/`)
- Auth header on every request: `Authorization: MediaBrowser Client="Luminary", Device="…", DeviceId="…",
  Version="…", Token="…"`. Keep a persistent random DeviceId. Sign in with POST `/Users/AuthenticateByName`.
  On launch validate with GET `/Users/Me`: a 401 signs out, a network error keeps you signed in.
- Jellyfin 10.9+ routes: `/UserViews`, `/UserItems/Resume`, `/Items/Latest`, `/Shows/NextUp`, `/Items`,
  `/Items/{id}`, `/Shows/{id}/Seasons`, `/Shows/{id}/Episodes`, `/Items/Filters`, `/MediaSegments/{id}`.
- Next Up on Home uses `enableResumable=false` so it doesn't repeat Continue Watching.
- Filters: tags and genres are `|`-separated (any-of; a comma matches nothing), years comma-separated; filter
  categories combine with AND.
- Playback: POST `/Items/{id}/PlaybackInfo` with a DeviceProfile (see `Models/PlaybackInfo.swift`): direct play for
  everything mpv handles; transcode profile HLS fMP4, HEVC/H.264. Direct stream URL:
  `/Videos/{id}/stream?static=true&mediaSourceId=…`. Send the token as an mpv `http-header-fields` header,
  not in the URL. Kill the transcode on stop: DELETE `/Videos/ActiveEncodings`.
- Reporting: `/Sessions/Playing`, `/Sessions/Playing/Progress` every 10 s and on pause, `/Sessions/Playing/Stopped`.
- Quality menu: only offer bitrates under 85 % of the source, and send `MaxWidth` on transcodes so the labels are
  true. Subtitles while transcoding: text → external file (keeps ASS styling), image (PGS) → burned in.
- Map Jellyfin's default audio/subtitle stream indexes onto mpv track ids by container stream index.

## mpv behaviour to match (see `../Sources/Luminary/Player/`)
- Never call libmpv from the UI thread except the render callback; commands go through a queue, events on their
  own thread, results posted back to the UI.
- `sub-ass-override=no`, embedded fonts on, shader cache directory set, keep-alive for HTTP streams.
- Resizing and full screen must be instant with no stretched frames (the hardest-won fix on Mac).
- The Skip Intro button hides 5 s after the segment starts and returns with the controls.
