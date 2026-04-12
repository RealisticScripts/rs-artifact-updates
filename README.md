# rs-artifact-updates

A production-ready FiveM resource that notifies when new **FiveM server artifacts** are available.

It checks the official FiveM Windows server artifacts feed, detects your server's current artifact build from the built-in `version` convar, and reports status through both the **server console** and **Discord webhook logging**.

## Features

- Detects the current FXServer artifact build automatically
- Checks the latest listed artifact from the official FiveM artifacts feed
- Reads the latest recommended and optional artifact values
- Sends update notifications to the server console
- Sends update notifications and status/error events to Discord
- Includes verbose debug logging for troubleshooting
- Includes the required GitHub release version check block

## Files

- `fxmanifest.lua` - resource manifest
- `config.lua` - check interval, debug mode, and Discord webhook
- `server.lua` - artifact polling, logging, and version check
- `LICENSE` - MIT license
- `README.md` - setup and usage

## Installation

1. Place the `rs-artifact-updates` folder in your server `resources` directory.
2. Set your Discord webhook in `config.lua`.
3. Add the resource to your `server.cfg`:

```cfg
ensure rs-artifacts-updates
```

## Configuration

```lua
Config = {}
Config.CheckIntervalMinutes = 60
Config.Debug = false
Config.DiscordWebhook = ''
```

### Configuration Reference

- `Config.CheckIntervalMinutes` - how often the resource checks for new artifacts
- `Config.Debug` - enables verbose debug logging in the console
- `Config.DiscordWebhook` - Discord webhook URL used for update/status/error logs

## Console Logging

The resource always logs to the server console. Example output:

```text
[rs-artifacts-updates] Resource started. Check interval: 60 minute(s). Debug: off
[rs-artifacts-updates] Current artifact build: 27417 | Latest listed: 28009 | Latest recommended: 25770 | Latest optional: 7290
[rs-artifacts-updates] A new FiveM artifact is available. Current: 27417 | Latest listed: 28009
```

## Discord Logging

Discord logging is built in. The resource sends webhook messages for:

- resource startup
- successful checks
- new artifact availability
- newly listed artifacts detected during polling
- parse / request failures

## Debug Logging

Set `Config.Debug = true` to print detailed diagnostics, including:

- raw `version` convar value
- parsed current build
- polling interval normalization
- HTTP request status
- parsed remote artifact values
- Discord webhook response failures

## Notes

- This resource does **not** download or install artifacts automatically.
- It checks the official Windows master artifacts listing:
  - `https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/`
- Discord logging requires a valid webhook URL.

## Versioning

This release uses the required resource version format:

- `v1.0.0`

## License

MIT License © 2026 Realistic Scripts
