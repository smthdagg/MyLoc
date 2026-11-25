# MyLoc

**MyLoc** is an independent, open-source iOS 26.0+ (iOS 27 compatible) location simulation tool for developers and testers, built with SwiftUI + MapKit and a Rust engine powered by the MIT-licensed [`idevice`](https://github.com/jkcoxson/idevice) crate.

[中文文档 / Chinese Guide](README_ZH.md)

---

## Features

- **Fixed Location Simulation**: Tap anywhere on the map, search globally, or enter `latitude, longitude` directly. Live target switching without reconnecting, with 4-second keep-alive heartbeat.
- **Global Search & Quick Cities**: Worldwide search (`MKLocalSearch` + `CLGeocoder` + built-in global city presets) and region-aware coordinate handling (automatic GCJ-02 ↔ WGS-84 conversion inside Mainland China only; passthrough for HK, Macau, Taiwan, Europe, Americas).
- **Route Simulation**: Apple Maps walking/cycling/driving routes with straight-line fallback, configurable pace, pause/resume/reverse, virtual joystick, and GPX 1.1 import/export.
- **Favorites, History & Crash Recovery**: Manage favorites, recent 30 history items, and explicit session recovery prompts after unexpected termination.
- **Privacy First**: Zero telemetry, zero analytics, zero backend servers. Pairing files are stored exclusively in the device Keychain (`WhenUnlockedThisDeviceOnly`).
- **Free Apple ID Friendly**: Single-target app (no App Extensions required), compatible with SideStore / AltStore / Sideloadly and external **LocalDevVPN**.

---

## Prerequisites

1. **iPhone** running **iOS 26.0+** with **Developer Mode** enabled (`Settings → Privacy & Security → Developer Mode`).
2. **LocalDevVPN** installed from the App Store (provides the local `10.7.0.1:49152` loopback tunnel).
3. A computer (macOS / Windows / Linux) **once** to generate your device's `.mobiledevicepairing` (`RpPairingFile`).

---

## Installation & Pairing Guide

### Step 1: Install `MyLoc.ipa`
- Download `MyLoc.ipa` from [Releases](../../releases) (or build from source below).
- Sideload `MyLoc.ipa` onto your iPhone using **SideStore**, **AltStore**, **Sideloadly**, or **Xcode** with your free Apple ID.
- Trust your developer certificate in `Settings → General → VPN & Device Management`.

### Step 2: Generate Your Device Pairing File (One-Time, Per Device)
Because iOS 26 requires USB trust for initial Remote Pairing, each iPhone needs its own `.mobiledevicepairing` file:

**Option A — Using `idevice_pair` (Windows / macOS / Linux)**
1. Connect your iPhone to your computer via USB, unlock it, and tap **Trust**.
2. Run [`idevice_pair`](https://github.com/jkcoxson/idevice_pair) and export the `.mobiledevicepairing` file.

**Option B — Using the built-in `export_pairing` CLI (macOS / Linux)**
```bash
cargo run --manifest-path Rust/myloc-engine/Cargo.toml --bin export_pairing -- <YOUR_UDID> my_iphone.mobiledevicepairing
```

### Step 3: Import & Start Simulating
1. Transfer the `.mobiledevicepairing` file to your iPhone's **Files** app (via AirDrop, iCloud Drive, etc.).
2. Open **MyLoc → Settings (or Top Status Pill) → Select `.mobiledevicepairing` File**.
3. Open **LocalDevVPN** and turn on the local tunnel.
4. Return to **MyLoc**, tap any location on the map (or pick a global city), and tap **Start Location Simulation**.
5. Tap **Stop & Restore** when finished to return to real GPS.

---

## Build From Source

Requirements: macOS with Xcode 26/27+, Rust (`aarch64-apple-ios` & `aarch64-apple-ios-sim` targets).

```bash
# 1. Run Rust unit tests & build MyLocEngine.xcframework
cargo test --manifest-path Rust/myloc-engine/Cargo.toml
./scripts/build-rust-xcframework.sh

# 2. Run Swift core unit tests
swift test --package-path MyLocCore

# 3. Generate Xcode project
python3 scripts/generate-xcodeproj.py

# 4. Open MyLoc.xcodeproj in Xcode, select your Apple ID Team, and Run
open MyLoc.xcodeproj
```

---

## License & Third-Party Notices

MyLoc is released under the [MIT License](LICENSE). See [THIRD_PARTY.md](THIRD_PARTY.md) for third-party open-source notices (`idevice`).
