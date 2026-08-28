# arxa-studio-mobile — deploy

This stage holds store-deployment evidence: fastlane lanes and receipts for
TestFlight/App Store and Play internal/production, plus Shorebird OTA patch
records.

What starts it: a released-green review in `../review/`. The
`arxa-deployer` skill owns the mechanics; stores are production and are
never touched without an explicit go.
