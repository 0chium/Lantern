# Unreleased Stage 1 diagnostic

Build ID: lantern-b51-diag-s1-20261010-r1.
Version: 0.1.2-1+diag.s1.20261010.r1; same package ID, no co-installation.
Based on verified Build 51 commit 82e4d8e8c4b28af822ade2ab508b821350ddddb0.
Both camera tweak and CCSupport module are required. Passive opt-in records only;
software cannot verify physical warm LED output. Source/runtime code matches the
independently reviewed Stage 1 copy. No new Apple hooks or power fallback.

Manual workflow_dispatch only, on diagnostics/lantern-b51-diag-s1-20261010-r1.
This public branch and Actions artifact are publicly readable with GitHub access;
"private" means unpublished diagnostic, not confidential. No release/APT/Pages.
Never merge this experimental workflow/source into main as a release update.

Artifacts include a uniquely named .deb, source locks, SHA256SUMS, package/slice
inspection, Theos submodule revisions, SDK archive hash, tool environment and
build log. Review before any device install. Runtime permissions and performance
remain unverified. Toolchain master/runner labels are mutable; recorded versions
are actual new build provenance, not a claim of exact Build 51 reproduction.
