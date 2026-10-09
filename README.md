# Lantern 0.1.2-1

![Lantern ON presentation](https://0chium.github.io/Lantern/assets/Lantern-public-on.png)

*Standalone accepted Build #51 ON header artwork, with transparent square padding.*

Warm/yellow flashlight control for iOS Control Center, with Apple's native expanded intensity slider and a custom lantern illustration.

## Supported environment

Verified on iPhone SE (2nd generation), iPhone12,8, running iOS 18.2 (22C152) with Dopamine 3.0.10 rootless. The tested environment includes CCSupport 1.3.13-3~ios18fix1. Other devices, iOS versions, jailbreaks and CCSupport versions are unverified. Sileo and Zebra repository-client validation is pending.

## Known limitations

- Switching between Lantern and Apple's flashlight at the same brightness may require a second interaction to update the physical flashlight output.
- Apple's expanded flashlight intensity interface can display its active indicator while Lantern is operating.

## Installation, updates and removal

Publication preparation: the repository is initially unsigned and not yet published. Live Sileo/Zebra compatibility validation is required; do not disable global package-manager authentication to use it.

Proposed source: `https://0chium.github.io/Lantern/` (not yet published/live-validated). Prepared links: [Add to Sileo](sileo://source/https://0chium.github.io/Lantern/) and [Add to Zebra](zbra://sources/add/https://0chium.github.io/Lantern/).

Once published and validated, add the confirmed HTTPS URL, refresh sources, and install Lantern. CCSupport is required to load the custom module. The metadata-only release candidate `0.1.2-1` declares `mobilesubstrate, com.opa334.ccsupport`; its installed contents are identical to accepted Build #51. The original Build #51 package remains preserved unchanged.

Add Lantern using Control Center's editing controls. Tap for warm light; long-press for the expanded intensity slider. The stock flashlight remains available for white light.

Use the package manager's normal update/remove action for Lantern. Turn the flashlight off before changing or removing the package. This package contains no automatic restart maintainer scripts. On the verified environment, activation requires restarting cameracaptured and reloading SpringBoard. A SpringBoard respring alone is not the verified complete procedure.

The established root-shell procedure is:

```sh
/var/jb/usr/bin/killall -TERM cameracaptured
/var/jb/usr/bin/sbreload
```

These are explicit activation operations, not commands automatically performed by this package. They interrupt Camera and Control Center processes; close Camera before proceeding. Use the supported environment only. Package-manager installation/removal and these activation steps together still require release-client validation before publication. Do not upgrade unrelated packages merely to install Lantern.

## Troubleshooting and support

Check the supported environment, installed package version, CCSupport prerequisite and Control Center configuration. For incorrect color at matching brightness, review the known limitation above. If a crash or Safe Mode occurs, stop testing and preserve existing evidence without deliberately reproducing it.

Report problems through https://github.com/0chium/Lantern/issues/new?template=bug_report.yml with device, iOS/build, jailbreak, Lantern version and exact observations. Review attachments for private information before posting. Request features through the existing feature-request form.

## Artifact verification

Release candidate: com.ochium.lantern 0.1.2-1, iphoneos-arm64 (Build #51 payload, dependency-only revision).

SHA-256:
`0456e46ca5000f2218d023f39b6d29f1f415b354d89b2a8cbf73a4da09b295a8`

Preserved original Build #51 SHA-256: `098ed281b45d68f5214b183daf37763852beb755338c5c9e18e7ebc687ebc904`.

The working implementation and artwork correspond to accepted commit `82e4d8e8c4b28af822ade2ab508b821350ddddb0`. Release-source control metadata additionally records version `0.1.2-1` and the CCSupport dependency. The distributed candidate is a verified metadata-only repack of Build #51, not a newly compiled artifact. Do not substitute diagnostic builds with the same version number.

## License

Original Lantern code and project-authored build configuration/documentation are licensed under MIT; see `LICENSE`. The copyright notice uses “2026 Lantern contributors.” This scope excludes `Resources/*.png`, Apple-owned material and third-party reference material. The six custom PNGs have independent design/editing provenance, with stock imagery used as reference only; redistribution of these six unmodified PNGs as part of Lantern is permitted with attribution to Lantern contributors under `ARTWORK_PERMISSION.md`, not MIT. No Apple or third-party research reference files are included in the release-source snapshot.
