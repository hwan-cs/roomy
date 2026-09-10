# Roomy 💾

See where your Mac's storage actually went — a visual map of your whole disk, plus one-click cleanup for the space you didn't know you could get back.

![Storage Map](https://github.com/user-attachments/assets/eff22623-654f-4656-89fa-7b6e0d303bda)

## Why

Your Mac always seems to be full. The disk cleaners that promise to fix it? Yet another subscription(boo), and Apple's own Storage tab doesn't fully show what's actually reclaimable.
Disk cleanup shouldn't require anything proprietary. Roomy does exactly that, for free.

## Features

- **Storage Map** — a full-disk treemap that streams in as it scans. Biggest folder = biggest shape. Double-click in to drill down, breadcrumb back out.
- **Curated categories** — plain-language cards for the specific kinds of hidden space: Photos & Videos, Messages & Mail attachments, Leftover App Data, Old iPhone Backups, Time Machine Local Snapshots, Forgotten Large Files, Caches & Logs, Trash.
- **Free Up Space** — everything Roomy considers safe (or worth a second look) to reclaim, gathered from across the whole disk and grouped by confidence, with one button to act on all of it.
- **Duplicate Finder** — finds exact-content duplicates anywhere already scanned, something Finder has no way to do on its own.
- **Menu bar companion** — free space at a glance, one click to open the main window or empty the Trash.

Every deletion goes to the Trash — reversible by default.

## Screenshots

| | |
|---|---|
| ![Downloads drill-down](https://github.com/user-attachments/assets/ac4f3c6c-71bc-4176-9cf9-9f456f42819e) | ![Free Up Space](https://github.com/user-attachments/assets/66586a45-1ddf-4a57-bfb4-a325ff3a0e2e) |
| ![Forgotten Large Files](https://github.com/user-attachments/assets/b6460ef1-13e1-4fdd-8e12-4e9d25790575) | ![Developer folder breakdown](https://github.com/user-attachments/assets/3518b49e-69e9-4fa9-927d-e19a0693a7c3) |

## Why Full Disk Access?

Roomy reads Photos/Mail/Messages caches, other apps' container data, and Time Machine local snapshots to find space that's otherwise invisible. None of that is readable without Full Disk Access! 
That permission is incompatible with the App Sandbox, which is why Roomy isn't on the Mac App Store and ships as a direct, notarized download instead. Roomy makes no network calls, collects no analytics, and sends nothing anywhere.

**Furthermore, Roomy is fully open source :P if you're suspicious go read the code!**

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon

## Build from Source

Roomy uses [Tuist](https://tuist.io) to generate its Xcode project (the `.xcodeproj`/`.xcworkspace` are gitignored, not checked in).

```sh
tuist generate
open Roomy.xcworkspace
```

Or build from the command line:

```sh
xcodebuild -workspace Roomy.xcworkspace -scheme Roomy build
```

## License

MIT — see [LICENSE](LICENSE).
