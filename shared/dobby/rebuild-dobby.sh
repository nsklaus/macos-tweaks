#!/bin/bash
# Rebuilds libdobby.a (Dobby, github.com/jmpews/Dobby, Apache-2.0) at a pinned revision with
# dobby_patch.diff applied. Copied from BackToCatalina (Source/rebuild-dobby.sh), minus its
# regression test step (the test file is not in BackToCatalina's tree).
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
output="${1:-$script_dir/libdobby.a}"
revision=5dfc8546954ce3b3198132ab13fddb89ee92cdd7
archive_sha=01a417233c40929aa21098c8a9724c00f6f05b5cde3f11abcac84b8e00053748
for tool in curl shasum tar git cmake ninja xcrun; do
    command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done
work="$(mktemp -d /tmp/btc-dobby.XXXXXX)"
echo "Dobby source/build logs retained at: $work"
curl --fail --location --retry 3 \
    "https://codeload.github.com/jmpews/Dobby/tar.gz/$revision" -o "$work/source.tar.gz"
echo "$archive_sha  $work/source.tar.gz" | shasum -a 256 -c -
tar -xzf "$work/source.tar.gz" -C "$work"
source_dir="$work/Dobby-$revision"
git -C "$source_dir" apply --check "$script_dir/dobby_patch.diff"
git -C "$source_dir" apply "$script_dir/dobby_patch.diff"

export SOURCE_DATE_EPOCH=1700000000
export ZERO_AR_DATE=1
sdk="$(xcrun --sdk macosx --show-sdk-path)"
archives=()
for arch in x86_64 arm64 arm64e; do
    build="$work/$arch"
    cmake -S "$source_dir" -B "$build" -G Ninja \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_SYSROOT="$sdk" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
        -DCMAKE_C_COMPILER="$(xcrun -f clang)" \
        -DCMAKE_CXX_COMPILER="$(xcrun -f clang++)" \
        -DCMAKE_C_FLAGS="-ffile-prefix-map=$work=/btc-dobby" \
        -DCMAKE_CXX_FLAGS="-ffile-prefix-map=$work=/btc-dobby" \
        -DDOBBY_BUILD_SILICON=ON -DDOBBY_DEBUG=OFF \
        -DDOBBY_BUILD_TEST=OFF -DDOBBY_BUILD_EXAMPLE=OFF \
        -DPlugin.SymbolResolver=ON > "$work/configure-$arch.log" 2>&1 || {
            cat "$work/configure-$arch.log"; exit 1;
        }
    cmake --build "$build" --target dobby_static > "$work/build-$arch.log" 2>&1 || {
        cat "$work/build-$arch.log"; exit 1;
    }
    archives+=("$build/libdobby.a")
done
xcrun lipo -create "${archives[@]}" -output "$work/libdobby.a"
[[ "$(xcrun lipo -archs "$work/libdobby.a")" == "x86_64 arm64 arm64e" ]]
xcrun otool -l "$work/libdobby.a" | awk '
    $1 == "minos" { count++; if ($2 != "12.0") exit 1 }
    END { if (!count) exit 1 }
'
if [[ -f "$output" ]]; then cp "$output" "$work/libdobby.previous.a"; fi
cp "$work/libdobby.a" "$output"
echo "Built $output (x86_64, arm64, arm64e; macOS 12.0)"
shasum -a 256 "$output"
