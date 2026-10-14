# ORLib

Library for OpenRemote iOS applications.

## Requirements

- iOS 15.0+
- Swift 5.5+
- Xcode 16.0+

## Installation

### Swift Package Manager

ORLib is available through [Swift Package Manager](https://swift.org/package-manager/).

To add ORLib to your Xcode project using Swift Package Manager:

1. In Xcode, select **File > Swift Packages > Add Package Dependency...**
2. Enter the repository URL: `https://github.com/openremote/ORLib.git`
3. Specify the version or branch you want to use
4. Select the ORLib package product

## Usage

```swift
import ORLib

// Your code using ORLib
```

### Push notifications

ORLib does not depend on Firebase, the app sets it up. On every launch path, including launches from a notification, call `FirebaseApp.configure()` and set `Messaging.messaging().delegate` before the console enables push. Firebase only issues the FCM token once it has the APNs token. With method swizzling disabled (`FirebaseAppDelegateProxyEnabled` set to `NO`), forward it yourself:

```swift
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
}
```

Then forward the notification and Firebase messaging callbacks from your `AppDelegate` to `ORNotificationHandler`:

```swift
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(ORNotificationHandler.shared.willPresent(notification))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        ORNotificationHandler.shared.didReceive(response)
        completionHandler()
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        ORNotificationHandler.shared.didReceiveRegistrationToken(fcmToken)
    }
}
```

If push is enabled before Firebase delivers the token (first launch), the push provider waits for it before replying, so the token is included in the console registration. The wait is capped at 4.5 s, just under the web console's 5 s provider timeout. A token that arrives later, or a rotated token, reaches the backend the next time the console enables push.

## License

ORLib is available under the AGPL-3.0 license. See the LICENSE.txt file for more info.

## SwiftLint

This project includes a configuration for [SwiftLint](https://github.com/realm/swiftlint).  
SwiftLint is called as a phase as part of the Xcode project build.
This phase expects that swiftlint has been installed on the machine running that build.

If building using SwiftPM (or opening the Package.swift file in Xcode), no linting step is performed during the build.  
This is on purpose, to avoid dependencies on SwiftLint in projects depending on this package.  
You can manually perform linting by running `swiftlint lint ORLib`.  

## Protocol Buffer file

The ESPProvision provider uses Protocol Buffer to communicate with the ESP32 device.  
The protobuf data specification is defined in the ORConfigChannelProtocol.proto file.  
Compiling this to Swift code is performed manually using the protoc compiler by the developer
and the resulting Swift code is committed in the repository as part of the source code.   
As indicated in [Generating stubs | Documentation](https://swiftpackageindex.com/grpc/grpc-swift-protobuf/2.1.2/documentation/grpcprotobuf/generating-stubs),
Protobuf compilation should not be part of the library build steps as it cannot be guaranteed to the library consumer has protoc available.
