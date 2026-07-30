# Native macOS webcam recorder

A small command-line webcam and microphone recorder using Apple's AVFoundation capture APIs.

## Requirements

- macOS
- Xcode Command Line Tools (`xcode-select --install`)

## Build

```bash
chmod +x build.sh
./build.sh
```

The build embeds camera and microphone permission descriptions in the executable. This is important: a plain command-line binary without those descriptions may not receive macOS capture permissions correctly.

## First run

```bash
./webcam-record --list-devices
./webcam-record -o recording.mov
```

macOS should ask Terminal (or your terminal application) for camera and microphone access. If access was previously denied, open:

**System Settings → Privacy & Security → Camera / Microphone**

and enable your terminal application.

## Usage

```text
webcam-record [options]

-o, --output PATH          Output QuickTime movie (default: recording.mov)
-d, --duration SECONDS     Stop automatically after this many seconds
    --camera TEXT          Camera name or unique-ID substring
    --microphone TEXT      Microphone name or unique-ID substring
    --preset VALUE         high, 720p, or 1080p
    --list-devices         List cameras and microphones
-h, --help                 Show help
```

Examples:

```bash
./webcam-record -o demo.mov
./webcam-record -o demo.mov --duration 30
./webcam-record -o demo.mov --preset 720p
./webcam-record --camera "MacBook Pro Camera" \
  --microphone "MacBook Pro Microphone" \
  -o demo.mov
```

Press **Ctrl+C** to stop. The utility waits for AVFoundation to finalize the movie before exiting.

## Install globally

```bash
sudo cp webcam-record /usr/local/bin/
webcam-record -o ~/Desktop/recording.mov
```

## Notes

- The native recording container is QuickTime Movie (`.mov`).
- The recorder requests H.264 when the selected output supports it.
- Device selection accepts an exact name, a partial name, or a unique ID.
