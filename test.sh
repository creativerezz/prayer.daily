#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/checks
swiftc -target "$(uname -m)-apple-macosx14.0" Sources/PrayDaily/Timing.swift Tests/PrayDailyTests/TimingTests.swift -o .build/checks/timing-tests
.build/checks/timing-tests
swiftc -target "$(uname -m)-apple-macosx14.0" -parse-as-library Sources/PrayDaily/Timing.swift Sources/PrayDaily/Preferences.swift Sources/PrayDaily/PrayerService.swift Sources/PrayDaily/Reminders.swift Sources/PrayDaily/NotificationService.swift Sources/PrayDaily/Model.swift Tests/PrayDailyTests/BehaviorTests.swift -o .build/checks/behavior-tests
.build/checks/behavior-tests "$@"
swiftc -target "$(uname -m)-apple-macosx14.0" -parse-as-library scripts/TestFlight/TestFlight.swift Tests/PrayDailyTests/TestFlightTests.swift -o .build/checks/testflight-tests
.build/checks/testflight-tests "$@"
