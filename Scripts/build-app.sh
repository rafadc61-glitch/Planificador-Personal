#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

sdk_path="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
if [[ ! -d "$sdk_path" ]]; then sdk_path="$(xcrun --sdk macosx --show-sdk-path)"; fi
export SDKROOT="$sdk_path"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/swift-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" dist

swift build --disable-sandbox -c release

stage="$(mktemp -d /private/tmp/planificador-build.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
app="$stage/Planificador Personal.app"
widget="$app/Contents/PlugIns/PlanificadorWidget.appex"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$widget/Contents/MacOS"
cp Scripts/AppInfo.plist "$app/Contents/Info.plist"
cp Scripts/WidgetInfo.plist "$widget/Contents/Info.plist"
cp .build/release/Planificador "$app/Contents/MacOS/Planificador"

swiftc -sdk "$sdk_path" -target arm64-apple-macosx14.0 \
    -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" \
    -parse-as-library -emit-executable -application-extension -module-name PlanificadorWidget \
    Sources/PlanificadorWidget/PlanificadorWidget.swift \
    -o "$widget/Contents/MacOS/PlanificadorWidget"

iconset="$project_root/.build/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" Assets/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -s format png -z "$retina" "$retina" Assets/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 Scripts/make_icns.py "$iconset" "$app/Contents/Resources/AppIcon.icns"

xattr -cr "$app"
codesign --force --sign - --entitlements Scripts/Planificador.entitlements "$widget"
codesign --force --sign - --entitlements Scripts/Planificador.entitlements "$app"
codesign --verify --deep --strict "$app"

archive="$project_root/dist/Planificador-Personal-macOS.zip"
versioned_archive="$project_root/dist/Planificador-Personal-macOS-0.6.zip"
rm -f "$archive" "$versioned_archive"
ditto -c -k --keepParent "$app" "$archive"
cp "$archive" "$versioned_archive"

if [[ -w "/Applications" ]]; then
    installed_app="/Applications/Planificador Personal.app"
    rm -rf "$installed_app"
    ditto "$app" "$installed_app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$installed_app" >/dev/null 2>&1 || true
    print "App actualizada en: $installed_app"
fi

print "App creada: $archive"
