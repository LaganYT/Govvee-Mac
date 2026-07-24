# Goveac

Native macOS app for controlling Govee lights and devices via the [Govee Open API](https://developer.govee.com/).

## Features

- Sign in with your Govee API key (stored in Keychain)
- Browse all devices on your account
- Organize devices into custom groups
- Power, brightness, color, and color temperature controls
- Toggles, modes, ranges, work modes, and sensor readings
- Light scenes, DIY scenes, and snapshots

## Requirements

- macOS 14+
- Xcode 15+
- A Govee Developer API key from https://developer.govee.com/

## Open & Run

```bash
cd "Govvee-Mac"
xcodegen generate
open Goveac.xcodeproj
```

Then select the **Goveac** scheme and press Run (⌘R).

Or build from the command line:

```bash
xcodegen generate
xcodebuild -scheme Goveac -configuration Debug build
```

## API

Uses `https://openapi.api.govee.com` with the `Govee-API-Key` header:

| Action | Endpoint |
|--------|----------|
| List devices | `GET /router/api/v1/user/devices` |
| Device state | `POST /router/api/v1/device/state` |
| Control | `POST /router/api/v1/device/control` |
| Scenes | `POST /router/api/v1/device/scenes` |
| DIY scenes | `POST /router/api/v1/device/diy-scenes` |
