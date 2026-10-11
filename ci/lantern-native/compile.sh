#!/bin/bash
# PREPARATION ONLY: run solely in an authorized ephemeral macOS CI workspace.
set -euo pipefail
test -z "$(git status --porcelain)"
infra="$GITHUB_WORKSPACE/infra/ci/lantern-native"
mkdir compile-evidence
exec > >(tee compile-evidence/complete.log) 2>&1
trap 'status=$?; printf "exit_status=%s\n" "$status" > compile-evidence/exit-status.txt' EXIT
test "$GITHUB_REPOSITORY" = 0chium/Lantern
test "$GITHUB_REF" = refs/heads/diagnostics/lantern-native-ci
test "$(git rev-parse HEAD)" = 82e4d8e8c4b28af822ade2ab508b821350ddddb0
test -d "$DEVELOPER_DIR"
test "$(xcodebuild -version)" = $'Xcode 16.4\nBuild version 16F6'
sw_vers
uname -m
xcodebuild -version
xcrun clang --version
# Some linker versions print version information but exit nonzero without inputs.
# Record that probe separately; compilation/link failure is never suppressed.
set +e
xcrun ld -v 2>&1
linker_version_status=$?
set -e
printf 'linker_version_probe_exit=%s\n' "$linker_version_status"
xcrun --find clang
xcrun --find ld
shasum -a 256 "$(xcrun --find clang)" "$(xcrun --find ld)"
git --version
make --version
perl -v
python3 --version
printf 'ImageVersion=%s\nImageOS=%s\n' "${ImageVersion:-unreported}" "${ImageOS:-unreported}"
python3 "$infra/validate_output.py" source "$infra/baseline-source-manifest.json"

# All changes are confined to this ephemeral checkout, never the accepted package.
mkdir _compile-toolchain
git init _compile-toolchain/theos
git -C _compile-toolchain/theos remote add origin https://github.com/theos/theos.git
git -C _compile-toolchain/theos fetch --depth=1 origin 304e0799973e8145f32e4ca2de6c747a84b758ce
git -C _compile-toolchain/theos checkout --detach FETCH_HEAD
git -C _compile-toolchain/theos submodule update --init --recursive
test "$(git -C _compile-toolchain/theos rev-parse HEAD)" = 304e0799973e8145f32e4ca2de6c747a84b758ce
git -C _compile-toolchain/theos submodule status --recursive | tee compile-evidence/theos-submodules.txt
if grep -Eq '^[+U-]' compile-evidence/theos-submodules.txt; then exit 1; fi
git init _compile-toolchain/sdks
git -C _compile-toolchain/sdks remote add origin https://github.com/theos/sdks.git
git -C _compile-toolchain/sdks config core.sparseCheckout true
mkdir -p _compile-toolchain/sdks/.git/info
printf '/iPhoneOS16.5.sdk/\n' > _compile-toolchain/sdks/.git/info/sparse-checkout
git -C _compile-toolchain/sdks fetch --depth=1 --filter=blob:none origin 0222fd5413cf4b9af096f37b4621afa2688572f7
git -C _compile-toolchain/sdks checkout --detach FETCH_HEAD
test "$(git -C _compile-toolchain/sdks rev-parse HEAD)" = 0222fd5413cf4b9af096f37b4621afa2688572f7
export THEOS="$PWD/_compile-toolchain/theos"
mkdir -p "$THEOS/sdks"
ln -s "$PWD/_compile-toolchain/sdks/iPhoneOS16.5.sdk" "$THEOS/sdks/iPhoneOS16.5.sdk"
python3 "$infra/validate_output.py" sdk "$THEOS/sdks/iPhoneOS16.5.sdk"

# No ldid installation and no fake backend approval. Disable optional signing
# only for these compile/link artifacts; nothing here can be packaged/deployed.
make all FINALPACKAGE=1 TARGET_CODESIGN= messages=yes
python3 "$infra/validate_output.py" binaries
for arch in arm64 arm64e; do
  xcrun clang -arch "$arch" -isysroot "$THEOS/sdks/iPhoneOS16.5.sdk" \
    -miphoneos-version-min=15.0 -std=c11 -Wall -Wextra -Werror -g \
    -c "$infra/native_logging_probe.c" -o "_compile-toolchain/native-log-$arch.o"
  xcrun clang -arch "$arch" -isysroot "$THEOS/sdks/iPhoneOS16.5.sdk" \
    -miphoneos-version-min=15.0 -dynamiclib "_compile-toolchain/native-log-$arch.o" \
    -o "_compile-toolchain/native-log-$arch.dylib"
  xcrun otool -L "_compile-toolchain/native-log-$arch.dylib" > "compile-evidence/native-log-$arch-loads.txt"
  xcrun otool -l "_compile-toolchain/native-log-$arch.dylib" > "compile-evidence/native-log-$arch-commands.txt"
  xcrun nm -u "_compile-toolchain/native-log-$arch.dylib" > "compile-evidence/native-log-$arch-imports.txt"
  shasum -a 256 "_compile-toolchain/native-log-$arch.o" "_compile-toolchain/native-log-$arch.dylib" > "compile-evidence/native-log-$arch-sha256.txt"
done
python3 "$infra/validate_output.py" finish
printf 'Compilation/link validation only. Runtime collection, hook safety and packaging NOT validated.\n' > compile-evidence/NOT-INSTALLABLE.txt

