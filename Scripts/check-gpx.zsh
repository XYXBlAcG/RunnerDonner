#!/bin/zsh
set -eu
cd "${0:A:h}/.."
mkdir -p .tmp
check_root=$(mktemp -d "$PWD/.tmp/gpx-check.XXXXXX")
trap 'rm -rf "$check_root"' EXIT
sources=(AppFailure.swift DeviceProtocol.swift Track.swift GPXDocument.swift)
swiftc -parse-as-library -target arm64-apple-macos13.0 -module-cache-path /tmp/runnerdonner-swift-cache "${sources[@]/#/LocationController/}" LocationController/GPXEditorModel.swift LocationController/tests/gpx-editor-check.swift -o "$check_root/editor-check"
"$check_root/editor-check"
Backend/.venv/bin/python Backend/tests/export_protocol_fixture.py "$check_root/session.json"
swiftc -parse-as-library -target arm64-apple-macos13.0 -module-cache-path /tmp/runnerdonner-swift-cache "${sources[@]/#/LocationController/}" LocationController/tests/device-protocol-check.swift -o "$check_root/protocol-check"
"$check_root/protocol-check" "$check_root/session.json" LocationController/tests/fixtures
swiftc -parse-as-library -target arm64-apple-macos13.0 -module-cache-path /tmp/runnerdonner-swift-cache "${sources[@]/#/LocationController/}" LocationController/GPXEditorModel.swift LocationController/Vendor/eviltransform/LocationTransform.swift LocationController/MapCoordinate.swift LocationController/tests/map-coordinate-check.swift -o "$check_root/map-check"
"$check_root/map-check"
