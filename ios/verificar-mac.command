#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! xcodebuild -version; then
  echo "Instala Xcode y selecciónalo con xcode-select antes de compilar."
  exit 1
fi
plutil -lint Info.plist BENM.xcodeproj/project.pbxproj
xcodebuild -resolvePackageDependencies -project BENM.xcodeproj -scheme BENM
xcodebuild -project BENM.xcodeproj -scheme BENM -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
echo "Compilación de simulador completada. Falta probar audio y alertas en un iPhone real."
