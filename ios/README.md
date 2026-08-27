# Roamline for iOS

Native SwiftUI companion app for the self-hosted Roamline server. It supports iOS 17 and later.

```bash
xcodegen generate
open Roamline.xcodeproj
```

The project uses Apple frameworks only: SwiftUI, MapKit, Core Location, PhotosUI, Security, and Foundation. There are no CocoaPods or Swift Package dependencies.

Location points are first persisted to `Application Support/Roamline/pending-locations.json`, then sent in idempotent batches. Auth tokens are kept in Keychain. Background tracking is active only during a journey explicitly started by the user.

Use a public HTTPS Roamline URL on physical devices. Simulator development also permits `http://localhost`.
