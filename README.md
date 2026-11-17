<p align="center"><img src="docs/icon.png" width="128" alt="The WhyFi icon: a floor plan glowing with Wi-Fi signal from the router, with a pin on the dead spot"></p>

<h1 align="center">WhyFi</h1>

<p align="center">Find out why your Wi-Fi drops. Carry your Mac around, say where you are and what you're doing, and WhyFi lines up what you said with the Wi-Fi signal and download speed at that moment.</p>

![WhyFi showing a walk through a house: the signal falls as the narration reaches "Standing right next to the dryer."](docs/screenshot.png)

*The screenshot shows a sample walk.*

## Why

I moved my router a few feet into the corner of my office, and my bedroom Wi-Fi dropped to about 50 Mbps while the office still got 150 to 300. My theory was the laundry room. It sits right on the straight line between the router and the bedroom, and a washer and dryer are two big metal boxes that could leave a shadow behind them where the signal doesn't reach. I wanted to test that by walking the house and talking through where I was, instead of running speed test after speed test and trying to remember where I'd been standing for each one.

WhyFi records the Wi-Fi measurements and your narration on one timeline. A drop at 2:13:02 lines up with "Standing right next to the dryer." Record a walk, change something (raise the router, add a mesh point), record the same walk again, and compare.

## What it records

- **Signal, every second:** strength (RSSI) and noise in dBm, the link rate, channel, band and channel width, and which access point you're on.
- **Download speed tests, one after another,** using Apple's built-in `networkQuality`. They're bound to the Wi-Fi interface, so they measure Wi-Fi even when the Mac is docked on Ethernet.
- **Your narration,** transcribed on your Mac by Apple's speech recognition. Each sentence becomes a numbered pin on the chart.

Audio and transcripts never leave your Mac. The only network traffic is the speed tests themselves.

## Requirements

- macOS 26 or later (Apple's on-device transcriber needs it)
- Xcode 26.6 or later to build

## Build and run

```bash
git clone https://github.com/timfurlong/whyfi.git
cd whyfi
open WhyFi.xcodeproj
```

Then press Run. The project signs with "Sign to Run Locally", so you don't need an Apple developer account. The catch is that macOS treats every rebuild as a new app and asks for the microphone and Location again. To stop that, sign with your own Apple Development certificate: copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` (it's gitignored) and put your team ID in it.

## Permissions

- **Microphone,** to hear your narration. Without it, WhyFi still records the Wi-Fi.
- **Location.** macOS only tells apps which access point you're connected to if they have Location access. WhyFi uses it to show when your Mac switches between a router and a mesh point. It never reads your location. Without it, everything else still works.
- The first run downloads Apple's English speech model, which macOS manages.

## Using it

1. Click **New Run** (⌘N), name it after what you're testing ("Router on shelf"), and click **Record**.
2. Walk around. Say where you are and anything that might matter: "In the hall," "Laptop facing the wall," "Next to the fridge."
3. Click **Stop** (⌘.).

To compare two setups, walk the same route in the same order each time, and stay about 30 seconds at each spot so a few speed tests finish there.

### Speed tests and data use

Back-to-back speed tests download about 1.5 GB a minute. If your plan has a data cap, switch to **Every 30 seconds** or **Off** in the toolbar or in Settings. Signal is recorded either way.

## Run files

Each run is a folder in `~/Library/Application Support/WhyFi/Runs/`. Right-click a run and choose **Show in Finder**.

| File | What's in it |
|---|---|
| `timeline.csv` | Every signal reading, speed test, sentence and event, one row each |
| `transcript.txt` | Your sentences, one per line: `[14:02:14] Standing next to the dryer.` |
| `run.json` | The run's name, start and end times, Mac and macOS version, speed test setting, and which permissions were granted |
| `audio.m4a` | Your narration. A run that ended in a crash keeps `audio.caf` instead |

`timeline.csv` columns: `time, elapsed_s, kind, rssi_dbm, noise_dbm, tx_rate_mbps, channel, band, width_mhz, bssid, download_mbps, responsiveness_rpm, text, end_time`.

- `kind` is `signal`, `speed`, `speech` or `event`.
- For `speed` and `speech` rows, `time` is when the test or sentence started and `end_time` when it ended. A speed row's `rssi_dbm` and `tx_rate_mbps` are averages over the test.
- Events include `run_started`, `run_stopped`, `wifi_disconnected`, `wifi_reconnected`, `access_point_changed <old> -> <new>`, `band_changed <old> -> <new>`, `speed_test_failed: <reason>`, `speech_unavailable: <reason>` and `location_denied`.
- Sentences are written a moment after you say them, so the file isn't strictly in time order. Sort by `time`.

## Analyze your runs with Claude

WhyFi records and shows. For the comparing, point an AI assistant like [Claude Code](https://claude.com/claude-code) at two run folders:

> Compare these two runs of the same walk. Where did the signal and speed drop, what was I describing at the time, and did moving the router help?

Your narration is what lets it line up places across runs, so say where you are.

## Development

- `scripts/test` runs the unit tests.
- `TEST_RUNNER_WHYFI_HARDWARE_TESTS=1 scripts/test` also runs the tests that need this Mac's Wi-Fi and speech recognition.
- The Xcode project is generated by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. Run `xcodegen generate` after adding or removing files.
- Set `WHYFI_RUNS_ROOT` to point the app at a different runs folder.
- The app icon is an Icon Composer file, `WhyFi/App/AppIcon.icon`. After changing it, render `docs/icon.png` with Icon Composer's `ictool`: `"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" WhyFi/App/AppIcon.icon --export-image --output-file docs/icon.png --platform macOS --rendition Default --width 256 --height 256 --scale 2`.

## Credits

The live transcription follows the approach in [Muesli](https://github.com/Muesli-HQ/muesli), and `TranscriptAccumulator.swift` is adapted from its code (MIT). See [NOTICE](NOTICE).

## License

MIT. See [LICENSE](LICENSE).
