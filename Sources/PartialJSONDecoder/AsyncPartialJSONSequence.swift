import Foundation

/// An `AsyncSequence` that transforms a sequence of bytes
/// into a sequence of values decoded from partial JSON.
///
/// This sequence attempts to decode partial JSON as it arrives,
/// emitting values as soon as valid JSON can be constructed.
public struct AsyncPartialJSONSequence<Base: AsyncSequence, T: Decodable & Equatable>: AsyncSequence
where Base.Element == UInt8 {
    /// The type of elements in the sequence.
    public typealias Element = (value: T, isComplete: Bool)

    /// The type of the iterator for the sequence.
    public typealias AsyncIterator = Iterator

    let base: Base
    let partialDecoder: PartialJSONDecoder
    let bufferSize: Int

    /// Creates a new `AsyncPartialJSONSequence` from a base sequence of bytes.
    /// - Parameters:
    ///   - base: Base async sequence of bytes
    ///   - partialDecoder: PartialJSONDecoder to use for decoding values
    ///   - bufferSize: Size to use for processing chunks (default: 1024)
    public init(
        base: Base,
        completer: JSONCompleter,
        decoder: JSONDecoder,
        bufferSize: Int = 1024
    ) {
        self.base = base
        self.partialDecoder = PartialJSONDecoder(
            completer: completer,
            decoder: decoder
        )
        self.bufferSize = bufferSize
    }

    /// Creates an iterator for the sequence.
    public func makeAsyncIterator() -> Iterator {
        return Iterator(
            base: base.makeAsyncIterator(),
            decoder: self.partialDecoder,
            bufferSize: bufferSize
        )
    }

    /// An iterator for the sequence.
    public struct Iterator: AsyncIteratorProtocol {
        var baseIterator: Base.AsyncIterator
        var buffer: [UInt8] = []
        var decoder: PartialJSONDecoder
        let bufferSize: Int
        var lastValue: T? = nil
        var hasEmittedValue = false
        var endOfSequence = false

        init(
            base: Base.AsyncIterator,
            decoder: PartialJSONDecoder,
            bufferSize: Int
        ) {
            self.baseIterator = base
            self.decoder = decoder
            self.bufferSize = bufferSize
        }

        public mutating func next() async throws -> Element? {
            while true {
                // 1. Handle End of Sequence first
                if self.endOfSequence {
                    if buffer.isEmpty {
                        return nil  // Stream ended, buffer empty, we are done.
                    }
                    // Stream ended, but buffer has remaining data. Attempt final decode.
                    do {
                        let result = try decoder.decode(T.self, from: Data(buffer))
                        // Even if identical to lastValue, emit as it's the final one.
                        buffer.removeAll()  // Clear buffer after final attempt
                        // Use result.isComplete for the final value's flag, but the sequence element marks true overall.
                        lastValue = result.value  // Update last value for consistency
                        hasEmittedValue = true
                        return (value: result.value, isComplete: true)
                    } catch {
                        buffer.removeAll()  // Clear buffer on final error attempt
                        // Handle final errors: Suppress key/value not found, potentially throw others
                        switch error {
                        case let decodingError as DecodingError:
                            switch decodingError {
                            case .keyNotFound, .valueNotFound:
                                return nil  // Suppress incomplete data errors at the end
                            default:
                                // Throw other decoding errors (e.g. dataCorrupted) only if nothing was ever emitted
                                if !hasEmittedValue { throw error } else { return nil }
                            }
                        default:
                            // Throw non-decoding errors only if nothing was ever emitted
                            if !hasEmittedValue { throw error } else { return nil }
                        }
                    }
                }

                // 2. Mid-Stream: Attempt Decode if buffer has data
                var emittedMidStream: Element? = nil
                if !buffer.isEmpty {
                    // Use try? to ignore decoding errors mid-stream
                    if let result = try? decoder.decode(T.self, from: Data(buffer)) {
                        let isNewValue = (lastValue == nil || result.value != lastValue)

                        if isNewValue {
                            lastValue = result.value
                            hasEmittedValue = true
                            // isComplete is false because self.endOfSequence is false here
                            emittedMidStream = (value: result.value, isComplete: false)

                            // Clear buffer ONLY if the decoder specifically reported this chunk as complete
                            // This allows for multiple top-level JSON objects/arrays in sequence
                            if result.isComplete {
                                buffer.removeAll()
                            }
                        }
                    }
                    // If try? returns nil (decode failed), we simply proceed to fetch more data
                }

                // 3. Return if a mid-stream value was prepared
                if let valueToEmit = emittedMidStream {
                    return valueToEmit
                }

                // 4. Fetch More Data (only if stream hasn't ended)
                do {
                    if let byte = try await baseIterator.next() {
                        buffer.append(byte)
                        // Loop back to attempt decode with new data
                    } else {
                        self.endOfSequence = true
                        // Loop back to handle termination logic
                    }
                } catch {
                    // Error during fetch, treat as fatal
                    buffer.removeAll()
                    throw error
                }
            }
        }
    }
}
