# Lantern 0.1.2-1

![Lantern icon](https://0chium.github.io/assets/Lantern-public-on.png)

Lantern adds warm/yellow flashlight control to iOS Control Center, using Apple's native expanded intensity slider. The stock flashlight remains available for white light.

Install the production release from [0chium's Repo](https://0chium.github.io/).

## Compatibility

| Status | Configuration | Evidence |
| --- | --- | --- |
| Verified working | iPhone SE (2nd generation), iPhone12,8; iOS 18.2 (22C152); Dopamine 3.0.10 rootless | Physical white/warm/off behavior verified on device. Tested with CCSupport 1.3.13-3~ios18fix1. |
| Tester-reported problem, not independently verified | iPhone 11 Pro; iOS 18.1.1; converted RootHide installation | Control Center control reportedly appears, but physical output remains white. Cause under investigation. |
| Tester-reported problem, not independently verified | iOS 16.5.1; other configuration details incomplete | Safe Mode reported. Cause and exact installed package not established. |
| Tester-reported functionality, not independently verified | Other iOS 18 configurations; details incomplete | Functionality reports do not establish support for every device, jailbreak or iOS 18 version. |
| Untested or unknown | Configurations not verified above | No compatibility claim. |

Sileo source refresh and the Lantern listing were verified on the reference device. This does not establish every installation, update or removal scenario. RootHide conversion alone is not confirmation of compatibility.

## Installation, updates and removal

1. Turn the flashlight off and close Camera before installing, updating or removing Lantern.
2. [Add to Sileo](sileo://source/https://0chium.github.io/), or manually add `https://0chium.github.io/` in Sileo's Sources.
3. Refresh sources and install **Lantern 0.1.2-1** through the package manager. Dependencies are `mobilesubstrate` and `com.opa334.ccsupport`; compatible CCSupport is needed for the Control Center module.
4. Complete activation below, then add Lantern using Control Center's editing controls. Tap for warm light; long-press to adjust brightness.

The APT repository is unsigned. Do not disable package-manager authentication globally.

<details>
<summary>Activation on the verified Dopamine rootless environment</summary>

The package has no automatic activation scripts. Restart `cameracaptured` and reload SpringBoard using the established root-shell procedure:

```sh
/var/jb/usr/bin/killall -TERM cameracaptured
/var/jb/usr/bin/sbreload
```

These operations interrupt Camera and Control Center. A SpringBoard respring alone is not the verified complete procedure. These commands are documented for the reference Dopamine rootless environment; RootHide activation and recovery remain unverified.

</details>

Use the package manager's normal update or remove action for Lantern. On the verified environment, repeat the activation procedure afterward to refresh loaded code. Do not upgrade unrelated packages merely to install Lantern.

## Known limitations and reported problems

- Switching between Lantern and Apple's flashlight at the same brightness may require a second interaction to update physical output.
- Apple's expanded flashlight intensity interface can display its active indicator while Lantern is operating.

The reported white-only and Safe Mode problems above remain unresolved. A visible Control Center control does not establish correct physical flashlight output. No root cause is confirmed for those reports.

## Troubleshooting and reporting

Check the installed Lantern version, compatibility table, CCSupport and whether Lantern was added to Control Center. If a crash or Safe Mode occurs, stop testing and preserve existing evidence; do not deliberately reproduce it to obtain logs.

- [Report compatibility](https://github.com/0chium/Lantern/issues/new?template=compatibility_report.yml), including successful and unsuccessful installations.
- [Report a bug](https://github.com/0chium/Lantern/issues/new?template=bug_report.yml).
- [Request a feature](https://github.com/0chium/Lantern/issues/new?template=feature_request.yml).

Reports and attachments are public. Never post passwords, tokens, Apple ID details, unique device identifiers or unredacted sensitive logs. Keep original logs locally and share only a redacted, relevant copy. Logs are optional; if you cannot share them safely, describe the observed behavior instead.

## Release verification

Production package: `com.ochium.lantern`, version `0.1.2-1`, architecture `iphoneos-arm64`.

[Download the accepted package](https://0chium.github.io/debs/com.ochium.lantern_0.1.2-1_iphoneos-arm64.deb).

SHA-256:
`0456e46ca5000f2218d023f39b6d29f1f415b354d89b2a8cbf73a4da09b295a8`

The implementation derives from accepted Build51 commit `82e4d8e8c4b28af822ade2ab508b821350ddddb0`. Version `0.1.2-1` is a metadata-only revision adding the CCSupport dependency; the installed Build51 payload is unchanged. Build57 and other diagnostic builds are experimental, not the production release. Use the accepted APT package rather than diagnostic branches or Actions artifacts for production installation.

## License

Original Lantern code and project-authored build configuration/documentation use the scoped [MIT license](LICENSE). Artwork has [separate redistribution permission](ARTWORK_PERMISSION.md), requires attribution to Lantern contributors, and is not licensed under MIT. Neither notice grants rights to Apple-owned or third-party reference materials.

Optional: [Support Development](https://ko-fi.com/0chium). Lantern is free and open-source; donations do not affect support or compatibility reporting.
