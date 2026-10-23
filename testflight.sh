#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/tools
swiftc -target "$(uname -m)-apple-macosx14.0" -parse-as-library scripts/TestFlight/TestFlight.swift scripts/TestFlight/TestFlightCLI.swift -o .build/tools/testflight
.build/tools/testflight "$@"
