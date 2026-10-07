# Lantern

Warm flashlight mode for iOS 18 Control Center, designed to preserve native iOS behavior.

## About

Lantern adds a separate warm/yellow flashlight control alongside the stock white flashlight. It preserves Apple's native intensity controls and Control Center experience, with mutually exclusive selection between the two modes.

## Tested environment

- iPhone SE (2nd generation), iPhone12,8, arm64e
- iOS 18.2, build 22C152
- Dopamine 3.0.10 rootless
- CCSupport 1.3.13-3~ios18fix1

Other devices, iOS versions, jailbreaks and CCSupport versions have not been verified. The package's architecture slices and deployment target are build properties, not broader compatibility claims.

## Installation

Public distribution is not available yet. Installation instructions will be added with the first public release.

## Usage

Add Lantern to Control Center using its editing controls. Tap Lantern for warm light, or the stock flashlight for white light. Long-press either control to use the native expanded intensity slider. Selecting one mode leaves the other unselected.

## Known limitation

When switching between the stock flashlight and Lantern from the expanded intensity control, selecting the exact intensity already in use may not immediately change the flashlight color. Changing the intensity causes the selected mode to apply.

## Bug reports and support

Use the [bug report form](https://github.com/0chium/Lantern/issues/new?template=bug_report.yml) for problems and the [feature request form](https://github.com/0chium/Lantern/issues/new?template=feature_request.yml) for suggestions.

Include your Lantern version, device, iOS/build, jailbreak version and the interaction you observed. For crashes, Safe Mode or unexpected restarts, attach the original crash or panic report when available rather than only a screenshot. Do not deliberately reproduce a crash just to obtain a report. Review attachments for private information before posting publicly.

## Development

Lantern aims to reuse Apple's native behavior and change only what the alternate flashlight mode requires, keeping hooks, dependencies, state and complexity small.

Lantern was developed with assistance from OpenAI Codex and extensive testing against the stock iOS flashlight implementation. The project intentionally stays as close to Apple's native behavior as possible, changing only what is necessary to provide the alternate flashlight mode. Lantern is an independent project and is not endorsed by Apple or OpenAI.

### Building

The existing GitHub Actions workflow builds with Theos on macOS. With Theos and the required SDK/toolchain already configured, the package command is:

```sh
make clean package FINALPACKAGE=1
```

The Makefile uses the rootless package scheme and builds arm64 and arm64e slices.

## License

License terms are pending an explicit final pre-publication decision. No project license has been selected or added.
