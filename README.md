# Succulent

[![Version](https://img.shields.io/cocoapods/v/Succulent.svg?style=flat)](http://cocoapods.org/pods/Succulent)
[![License](https://img.shields.io/cocoapods/l/Succulent.svg?style=flat)](http://cocoapods.org/pods/Succulent)
[![Platform](https://img.shields.io/cocoapods/p/Succulent.svg?style=flat)](http://cocoapods.org/pods/Succulent)
[![Build Status](https://travis-ci.org/cactuslab/Succulent.svg?branch=develop)](https://travis-ci.org/cactuslab/Succulent)

Succulent is a Swift library to provide API recording and replay for automated testing on iOS.

Succulent creates a local web server that you point your app to, instead of the live API. In recording
mode, Succulent receives the API request from the app and then makes the same request to the live API,
recording the request and response for future replay.

Succulent can also handle mutating requests, like POST, PUT and DELETE: after a mutating request Succulent
stores a new version of any subsequent responses, then correctly simulates the change during playback.

## Why?

Succulent solves the problem of getting repeatable API results to support stable automated testing.

## Example

Set up Succulent in your XCTestCase's `setUp` method:

```swift
var app: XCUIApplication!
var succulent: Succulent!

override func setUp() {
	super.setUp()

	self.app = XCUIApplication()

	if let traceUrl = self.traceUrl {
		// Replay using an existing trace file
		self.succulent = Succulent(replayFrom: traceUrl)
	} else {
		// Record to a new trace file
		// The "/" at the end of the base URL is required
		self.succulent = Succulent(recordTo: self.recordUrl, baseUrl: URL(string: "{YOUR-REAL-BASE-URL}/")!)
	}

	self.succulent.start()

	self.app.launchEnvironment["succulentBaseURL"] = "http://localhost:\(succulent.actualPort)/"
	self.app.launch()
}

/// The name of the trace file for the current test
private var traceName: String {
	return self.description.trimmingCharacters(in: CharacterSet(charactersIn: "-[] ")).replacingOccurrences(of: " ", with: "_")
}

/// The URL to the trace file for the current test when running tests
private var traceUrl: URL? {
	let bundle = Bundle(for: type(of: self))
	return bundle.url(forResource: self.traceName, withExtension: "trace", subdirectory: "Succulent")
}

/// The URL to the trace file for the current test when recording
private var recordUrl: URL {
    let bundle = Bundle(for: type(of: self))
    let recordPath = bundle.infoDictionary!["TraceRecordPath"] as! String
    return URL(fileURLWithPath: "\(recordPath)/\(self.traceName).trace")
}
```

Note that `recordUrl` uses a string that must be set up in your UI testing directory's `Info.plist` file:

```xml
	<key>TraceRecordPath</key>
	<string>$(PROJECT_DIR)/Succulent/</string>
```

You also need to give the target you are testing permission to connect to a local server. This is done by adding the following to the `Info.plist` of the target you are testing against:

```xml
	<key>NSAppTransportSecurity</key>
	<dict>
 		<key>NSAllowsLocalNetworking</key>
 		<true/>
	</dict>
```

With this setting, Succulent records trace files into your project source tree. Therefore your Succulent traces are committed to source control with your test files, and when you build and run your tests the traces are copied into the test application.

Finally, in your app, look for the `"succulentBaseURL"` environment variable, and use that URL in place
of your live API URL:

```swift
let apiBaseUrlString = ProcessInfo.processInfo.environment["succulentBaseURL"] ?? "{YOUR-REAL-BASE-URL}"
let apiBaseUrl = URL(string: baseUrlString)
```

There is an example project in the `Example` directory. To run the example project, run `pod install` from within the Example directory, then open the Xcode workspace and run the tests. The example project demonstrates some of the use of Succulent in a stand-alone setting rather than as it is intended, which is for UI automation testing of another app.

## Requirements

## Installation

Succulent is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod "Succulent"
```

## Authors

[Karl von Randow](https://github.com/karlvr), [Tom Carey](https://github.com/tomcarey)

## License

Succulent is available under the MIT license. See the LICENSE file for more info.
