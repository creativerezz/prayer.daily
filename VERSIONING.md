# Versioning

The current beta marketing version is **0.1.0**. Increment patches to 0.1.1, features to 0.2.0, and use 1.0.0 for the first stable release. Use numeric X.Y.Z only; do not append beta labels to the Apple marketing version.

The build number is a separate integer. Increment it for every upload, including a change in marketing version. Never reset or reuse accepted build numbers. Check the processed App Store Connect history first, then verify the final archive's CFBundleShortVersionString, CFBundleVersion and bundle identity.

For iOS, update MARKETING_VERSION and CURRENT_PROJECT_VERSION in Assets/ios/project.yml and regenerate with xcodegen generate --spec Assets/ios/project.yml. Keep Resources/Info.plist macOS version and build aligned. Internal Swift target `PrayDaily` and bundle IDs (`com.reza.praydaily`) stay unchanged.
