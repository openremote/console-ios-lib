# ORLib

Library for OpenRemote iOS applications.

## Requirements

- iOS 14.0+
- Swift 5.0+
- Xcode 12.0+

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

## License

ORLib is available under the AGPL-3.0 license. See the LICENSE.txt file for more info.

## Protocol Buffer file

The ESPProvision provider uses Protocol Buffer to communicate with the ESP32 device.  
The protobuf data specification is defined in the ORConfigChannelProtocol.proto file.  
Compiling this to Swift code is performed manually using the protoc compiler by the developer
and the resulting Swift code is committed in the repository as part of the source code.   
As indicated in [Generating stubs | Documentation](https://swiftpackageindex.com/grpc/grpc-swift-protobuf/2.1.2/documentation/grpcprotobuf/generating-stubs),
Protobuf compilation should not be part of the library build steps as it cannot be guaranteed to the library consumer has protoc available.
