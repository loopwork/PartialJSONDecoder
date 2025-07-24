# PartialJSONDecoder

A lightweight library for working with incomplete or streaming JSON in Swift.

## Features

- [x] Parse and decode incomplete JSON by intelligently completing missing closing characters
- [x] Streaming support via `AsyncSequence`
- [x] Decode JSON as it arrives, without waiting for complete chunks
- [x] Support for custom `JSONDecoder` configuration
- [x] Handles non-conforming float values like NaN and Infinity (configurable)

## Requirements

- Swift 6.0+ / Xcode 16+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/loopwork/PartialJSONDecoder.git", from: "1.0.0")
]
```

## Usage

### Basic Usage

Use the `PartialJSONDecoder` to decode JSON that might be incomplete:

```swift
import PartialJSONDecoder
import Foundation

// Create a model matching your JSON structure
struct Person: Codable, Equatable {
    let name: String
    let age: Int
    let hobbies: [String]
}

// Example with incomplete JSON
let partialJSON = #"{"name": "Alice", "age": 30, "hobbies": ["reading", "hiking"#
let decoder = PartialJSONDecoder()

do {
    let (person, isComplete) = try decoder.decode(Person.self, from: partialJSON)
    print("Decoded: \(person), Complete: \(isComplete)")
    // Output: Decoded: Person(name: "Alice", age: 30, hobbies: ["reading", "hiking"]), Complete: false
} catch {
    print("Error: \(error)")
}
```

### Using a Custom Decoder

You can provide your own `JSONDecoder` for custom decoding strategies:

```swift
import PartialJSONDecoder
import Foundation

struct LogEntry: Codable, Equatable {
    let timestamp: Date
    let level: String
    let message: String
}

// Set up a custom JSONDecoder with date decoding strategy
let jsonDecoder = JSONDecoder()
jsonDecoder.dateDecodingStrategy = .iso8601

// Create PartialJSONDecoder with the custom decoder
let partialDecoder = PartialJSONDecoder(decoder: jsonDecoder)

// Decode an incomplete log entry
let partialLog = #"{"timestamp": "2023-05-10T15:30:45Z", "level": "INFO", "message": "Starting"#
do {
    let (entry, isComplete) = try partialDecoder.decode(LogEntry.self, from: partialLog)
    print("[\(entry.timestamp)] [\(entry.level)] \(entry.message)")
    // Output: [2023-05-10 15:30:45 +0000] [INFO] Starting
    print("Was JSON complete? \(isComplete)")
    // Output: Was JSON complete? false
} catch {
    print("Error: \(error)")
}
```

## Streaming with AsyncSequence

For streaming scenarios, you can use the `partialJSON` method on any `AsyncSequence` of bytes:

```swift
import PartialJSONDecoder
import Foundation

struct Message: Codable, Equatable {
    let sender: String
    let content: String
}

Task {
    // Get a byte stream from a URL
    let url = URL(string: "https://api.example.com/stream")!
    let (bytes, _) = try await URLSession.shared.bytes(from: url)

    // Process each partial JSON message as it arrives
    for try await (message, isComplete) in bytes.partialJSON(decoding: Message.self) {
        // Update UI immediately with each partial message
        print("[\(message.sender)]: \(message.content)")

        // Optionally indicate if this was from a complete JSON object
        if !isComplete {
            print("(partial message, still receiving...)")
        }
    }
}
```

### Using a Custom Decoder with Streaming

You can provide your own `JSONDecoder` and `JSONCompleter` for custom decoding strategies:

```swift
import PartialJSONDecoder
import Foundation

struct DataPoint: Codable, Equatable {
    let timestamp: Date
    let value: Double
}

// Set up a custom JSONDecoder with date decoding strategy
let jsonDecoder = JSONDecoder()
jsonDecoder.dateDecodingStrategy = .iso8601

// Configure a custom JSONCompleter
let completer = JSONCompleter()
completer.nonConformingFloatStrategy = .convertFromString(
    positiveInfinity: "Infinity",
    negativeInfinity: "-Infinity",
    nan: "NaN"
)
completer.maximumDepth = 100 // Increase maximum nesting depth (default is 64)

// Use it with the streaming API
Task {
    let url = URL(string: "https://api.example.com/stream")!
    let (bytes, _) = try await URLSession.shared.bytes(from: url)

    // Pass the custom decoder and completer to the partialJSON extension
    for try await (data, isComplete) in bytes.partialJSON(
        decoding: DataPoint.self,
        with: jsonDecoder,
        using: completer
    ) {
        processData(data)
    }
}
```

## Advanced Usage

### Using the JSONCompleter Directly

You can also use the `JSONCompleter` to analyze or complete JSON manually:

```swift
import PartialJSONDecoder

let partialJSON = #"{"name": "Alice", "tags": ["swift", "json"#
let completer = JSONCompleter()

// Complete the JSON
let completedJSON = try completer.complete(partialJSON)
print(completedJSON)
// Output: {"name": "Alice", "tags": ["swift", "json"]}

// Or check what completion is needed
if let completion = try completer.completion(for: partialJSON, from: partialJSON.startIndex) {
    print("Needs completion: \(completion.string) at position \(completion.endIndex)")
    // Output: Needs completion: "]} at position [end of "json"]

    // Apply the completion manually
    let manuallyCompleted = partialJSON + completion.string
    print(manuallyCompleted)
    // Output: {"name": "Alice", "tags": ["swift", "json"]}
} else {
    print("JSON is already complete")
}
```

### Configuration Options

The `JSONCompleter` class offers configuration options:

```swift
// Configure how to handle non-conforming float values like NaN and Infinity
let completer = JSONCompleter()
completer.nonConformingFloatStrategy = .convertFromString(
    positiveInfinity: "Infinity",
    negativeInfinity: "-Infinity",
    nan: "NaN"
)

// Set maximum nesting depth for JSON objects/arrays to prevent stack overflow
completer.maximumDepth = 100 // Default is 64
```

## Example Use Cases

### LLM Streaming

Perfect for processing streaming responses from LLM APIs:

```swift
Task {
    let url = URL(string: "https://api.example.com/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode([
        "model": "gpt-4",
        "messages": [["role": "user", "content": "Tell me about Swift"]],
        "stream": true
    ])

    let (stream, _) = try await URLSession.shared.bytes(for: request)

    for try await (response, isComplete) in stream.partialJSON(decoding: LLMResponse.self) {
        // Update UI with each token as it arrives
        updateResponseText(with: response.choices.first?.delta.content)

        // Optionally indicate if this was a complete response
        if isComplete {
            print("Response complete")
        }
    }
}
```

### Progressive Data Visualization

Useful for visualizing data as it loads:

```swift
Task {
    let dataStream = getTimeSeriesDataStream() // Some AsyncSequence<UInt8>

    var dataPoints: [DataPoint] = []

    for try await (point, _) in dataStream.partialJSON(decoding: DataPoint.self) {
        // Add new point to dataset
        dataPoints.append(point)

        // Update visualization with latest data
        updateChart(with: dataPoints)
    }
}
```

## License

This project is available under the MIT license.
See the LICENSE file for more info.
