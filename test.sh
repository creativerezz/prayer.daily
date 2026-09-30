#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/checks
swiftc -target "$(uname -m)-apple-macosx14.0" Sources/Hilal/Timing.swift Tests/HilalTests/TimingTests.swift -o .build/checks/timing-tests
.build/checks/timing-tests
swiftc -target "$(uname -m)-apple-macosx14.0" -parse-as-library Sources/Hilal/Timing.swift Sources/Hilal/Preferences.swift Sources/Hilal/PrayerService.swift Sources/Hilal/Reminders.swift Sources/Hilal/NotificationService.swift Sources/Hilal/Model.swift Tests/HilalTests/BehaviorTests.swift -o .build/checks/behavior-tests
.build/checks/behavior-tests "$@"
