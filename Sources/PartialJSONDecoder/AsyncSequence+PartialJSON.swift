import Foundation

extension AsyncSequence where Element == UInt8 {
    /// Returns an asynchronous sequence of values decoded from partial JSON.
    /// This sequence will attempt to decode partial JSON as it arrives,
    /// emitting values as soon as valid JSON can be constructed, along with
    /// a flag indicating whether the JSON was complete.
    ///
    /// - Parameters:
    ///   - type: The type to decode the JSON to.
    ///   - decoder: The decoder to use for decoding JSON.
    ///   - completer: An optional custom JSONCompleter to use for completing partial JSON.
    ///   - bufferSize: The size of the buffer to use for processing chunks.
    /// - Returns: An asynchronous sequence of decoded values and completion flags.
    public func partialJSON<T: Decodable & Equatable>(
        decoding type: T.Type,
        with decoder: JSONDecoder = JSONDecoder(),
        using completer: JSONCompleter = JSONCompleter(),
        bufferSize: Int = 1024
    ) -> AsyncPartialJSONSequence<Self, T> {
        return AsyncPartialJSONSequence(
            base: self,
            completer: completer,
            decoder: decoder,
            bufferSize: bufferSize
        )
    }
}
