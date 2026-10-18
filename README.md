# Lantern 0.1.3-1

![Lantern icon](https://0chium.github.io/assets/Lantern-public-on.png)

**A warmer light. Right in Control Center.**

Tap Lantern for warm light. Press and hold to adjust brightness with Apple's native intensity slider. Keep the stock flashlight for white light.

No Settings pane or preferences to configure.

Install the production release from [0chium's Repo](https://0chium.github.io/).

## Compatibility

The physical results below were obtained with the accepted 0.1.2-1 release. Version 0.1.3-1 preserves its exact installed payload; testing of the newly versioned package upgrade is pending.

| Status | Configuration | Evidence |
| --- | --- | --- |
| Verified working | iPhone SE (2nd generation), iPhone12,8; iOS 18.2 (22C152); Dopamine 3.0.10 rootless | Physical white/warm/off behavior verified on device. Tested with CCSupport 1.3.13-3~ios18fix1. |
| Owner-verified working after activation | iPhone 11 Pro Max, iPhone12,5; iOS 18.3.2 (22D82); Dopamine 3 rootless; ElleKit 1.2; CCSupport installed | Lantern 0.1.2-1 installed; Control Center icon/brightness and physical warm/OFF, native white ON/OFF, and return to warm passed after the documented activation procedure below. Verified only on this configuration. |
| Owner-observed problem | iPhone 14 Pro, iPhone15,2; iOS 17.0 (21A329); Dopamine rootless | Selecting Lantern causes a SpringBoard crash and Safe Mode during Control Center initialization. Cause unknown; warm-light capability on iPhone 14 Pro is unverified. |
| Tester-reported problem, not independently verified | iPhone 11 Pro; iOS 18.1.1; converted RootHide installation | Control Center control reportedly appears, but physical output remains white. Cause under investigation. |
| Tester-reported problem, not independently verified | iOS 16.5.1; other configuration details incomplete | Safe Mode reported. Cause and exact installed package not established. |
| Tester-reported functionality, not independently verified | Other iOS 18 configurations; details incomplete | Functionality reports do not establish support for every device, jailbreak or iOS 18 version. |
| Untested or unknown | Configurations not verified above | No compatibility claim. |

Sileo source refresh and the Lantern listing were verified on the reference device. This does not establish every installation, update or removal scenario. RootHide conversion alone is not confirmation of compatibility.

## Install and use

1. Turn the flashlight off and close Camera before installing, updating or removing Lantern.
2. [Add to Sileo](sileo://source/https://0chium.github.io/), or manually add `https://0chium.github.io/` in Sileo's Sources.
3. Refresh sources and install **Lantern 0.1.3-1** through the package manager. Dependencies are `mobilesubstrate` and `com.opa334.ccsupport`; compatible CCSupport is needed for the Control Center module.
4. Complete activation below, then add Lantern using Control Center's editing controls. Tap for warm light; long-press to adjust brightness.

<details>
<summary>Activation on the owner-verified Dopamine rootless configurations</summary>

The package has no automatic activation scripts. Restart `cameracaptured` and reload SpringBoard using the established root-shell procedure:

```sh
/var/jb/usr/bin/killall -TERM cameracaptured
/var/jb/usr/bin/sbreload
```

On the iPhone 11 Pro Max configuration above, output was initially white only. Completing both activation steps enabled physical warm output, and SpringBoard returned without Safe Mode. Activation resolved the observed symptom; its precise internal cause was not independently established.

These operations interrupt Camera and Control Center. A SpringBoard respring alone is not the verified complete procedure. These commands are documented for the listed owner-verified Dopamine rootless configurations; RootHide activation and recovery remain unverified.

</details>

Use your package manager for updates and removal, then repeat the documented activation procedure on the verified environment. The repository is unsigned; keep package-manager authentication enabled.

## Known limitations and reported problems

- Switching between Lantern and Apple's flashlight at the same brightness may require a second interaction to update physical output.
- Apple's expanded flashlight intensity interface can display its active indicator while Lantern is operating.

The other white-only and Safe Mode reports in the compatibility table remain unresolved. A visible Control Center control does not establish correct physical flashlight output. No root cause is confirmed for those reports.

## Troubleshooting and reporting

Check the installed Lantern version, compatibility table, CCSupport and whether Lantern was added to Control Center. If a crash or Safe Mode occurs, stop testing and preserve existing evidence; do not deliberately reproduce it to obtain logs.

- [Report compatibility](https://github.com/0chium/Lantern/issues/new?template=compatibility_report.yml), including successful and unsuccessful installations.
- [Report a bug](https://github.com/0chium/Lantern/issues/new?template=bug_report.yml).
- [Request a feature](https://github.com/0chium/Lantern/issues/new?template=feature_request.yml).

Reports and attachments are public. Never post passwords, tokens, Apple ID details, unique device identifiers or unredacted sensitive logs. Keep original logs locally and share only a redacted, relevant copy. Logs are optional; if you cannot share them safely, describe the observed behavior instead.

## Release verification

Production package: `com.ochium.lantern`, version `0.1.3-1`, architecture `iphoneos-arm64`.

[Download Lantern 0.1.3-1](https://0chium.github.io/debs/com.ochium.lantern_0.1.3-1_iphoneos-arm64.deb).

SHA-256:
`652a6598e9cdb417e88f87219d2efb94d2e9b1a838a265074942a862c269c0fc`

The implementation derives from accepted Build51 commit `82e4d8e8c4b28af822ade2ab508b821350ddddb0`. Version `0.1.3-1` changes only the package version from `0.1.2-1`: all installed binaries and resources are byte-identical. No functional code, hooks, LED mapping, injection filters, dependencies or activation behavior changed. Build57 and other diagnostic builds are experimental, not the production release. Use the production APT package rather than diagnostic branches or Actions artifacts.

The previous [0.1.2-1 package](https://0chium.github.io/debs/com.ochium.lantern_0.1.2-1_iphoneos-arm64.deb) remains available for rollback; SHA-256: `0456e46ca5000f2218d023f39b6d29f1f415b354d89b2a8cbf73a4da09b295a8`.

Credit to [PoomSmart](https://github.com/PoomSmart) for earlier ISP LED-control work in [Amber](https://github.com/PoomSmart/Amber).

## License

Original Lantern code and project-authored build configuration/documentation use the scoped [MIT license](LICENSE). Artwork has [separate redistribution permission](ARTWORK_PERMISSION.md), requires attribution to Lantern contributors, and is not licensed under MIT. Neither notice grants rights to Apple-owned or third-party reference materials.

Optional: [Support Development](https://ko-fi.com/0chium). Lantern is free and open-source; donations do not affect support or compatibility reporting.
