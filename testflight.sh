#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
# ASC_KEY_ID / ASC_ISSUER_ID live in the gitignored .env.local; the .p8 stays in ~/.appstoreconnect/private_keys.
if [[ -f .env.local ]]; then set -a; source .env.local; set +a; fi
mkdir -p .build/tools
swiftc -target "$(uname -m)-apple-macosx14.0" -parse-as-library scripts/TestFlight/TestFlight.swift scripts/TestFlight/TestFlightCLI.swift -o .build/tools/testflight
.build/tools/testflight "$@"
