#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export PYINSTALLER_CONFIG_DIR="$PWD/Backend/.pyinstaller-cache"
Backend/.venv/bin/python Backend/generate_protocol.py
Backend/.venv/bin/python -m PyInstaller --noconfirm --clean --onedir --name DeviceBridge --distpath Backend/dist --workpath Backend/build --specpath Backend --recursive-copy-metadata pymobiledevice3 --collect-data pymobiledevice3 --collect-data developer_disk_image --exclude-module IPython --exclude-module tkinter --exclude-module matplotlib Backend/bridge.py > Backend/build.log 2>&1
mkdir -p .tmp dist
build_root=$(mktemp -d "$PWD/.tmp/build.XXXXXX")
app="$build_root/轨迹控制面板.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Licenses"
cp LocationController/Info.plist "$app/Contents/Info.plist"
cp LocationController/AppIcon.icns "$app/Contents/Resources/"
cp Backend/licenses/pymobiledevice3-LICENSE.txt "$app/Contents/Resources/Licenses/"
cp LocationController/Vendor/eviltransform/LICENSE "$app/Contents/Resources/Licenses/eviltransform-LICENSE.txt"
ditto Backend/dist/DeviceBridge "$app/Contents/Resources/DeviceBridge"
sources=(AppFailure.swift Track.swift GPXDocument.swift GPXEditorModel.swift Pace.swift DeviceProtocol.swift ModernBackend.swift Vendor/eviltransform/LocationTransform.swift MapCoordinate.swift MapPointPicker.swift GPXRouteMap.swift GPXEditor.swift ControlPanel.swift main.swift)
swiftc -parse-as-library -O -target arm64-apple-macos13.0 -module-cache-path /tmp/runnerdonner-swift-cache "${sources[@]/#/LocationController/}" -o "$app/Contents/MacOS/LocationController"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
if [[ -d 'dist/轨迹控制面板.app' ]]; then
    mv 'dist/轨迹控制面板.app' "$build_root/previous.app"
fi
mv "$app" 'dist/轨迹控制面板.app'
Backend/.venv/bin/python -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$build_root"
print 'dist/轨迹控制面板.app'
