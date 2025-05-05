import Foundation

/// Errors that can occur during partial JSON decoding.
public enum PartialJSONDecoderError: Error {
    /// The data is not valid UTF-8 data.
    case invalidUTF8Data

    /// Decoding failed with the specified error.
    case decodingFailed(Error)
}

/// A decoder that can handle partial JSON by attempting to complete it before decoding.
/// This is useful for streaming scenarios where you want to process incomplete JSON as it arrives.
public class PartialJSONDecoder {
    private let completer: JSONCompleter
    private let decoder: JSONDecoder

    /// Creates a new partial JSON decoder with a custom completer.
    /// - Parameters:
    ///   - completer: The JSON completer to use for completing partial JSON.
    ///   - decoder: The underlying JSON decoder to use for decoding completed JSON data.
    public init(
        completer: JSONCompleter = JSONCompleter(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.completer = completer
        self.decoder = decoder
    }

    /// Attempts to decode partial JSON data into a value of the specified type.
    ///
    /// - Parameters:
    ///   - type: The type of the value to decode from the given JSON data.
    ///   - data: The partial JSON data to decode.
    /// - Returns: A tuple containing the decoded value (if successful) and a Boolean indicating
    ///   whether the JSON was complete or had to be completed.
    /// - Throws: An error if the data cannot be decoded into the specified type.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> (
        value: T, isComplete: Bool
    ) {
        // First try to decode the data directly
        do {
            let value = try decoder.decode(type, from: data)
            return (value, true)  // JSON was complete
        } catch {
            // If direct decoding fails, try to complete the JSON first
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw PartialJSONDecoderError.invalidUTF8Data
            }

            let completedJson = try completer.complete(jsonString)
            guard let completedData = completedJson.data(using: .utf8) else {
                throw PartialJSONDecoderError.invalidUTF8Data
            }

            // Try decoding the completed data
            do {
                let value = try decoder.decode(type, from: completedData)
                return (value, false)  // JSON was incomplete and needed completion
            } catch {
                // If decoding the completed JSON fails, wrap and throw that specific error
                throw PartialJSONDecoderError.decodingFailed(error)
            }
        }
    }

    /// Attempts to decode partial JSON string into a value of the specified type.
    ///
    /// - Parameters:
    ///   - type: The type of the value to decode from the given JSON string.
    ///   - string: The partial JSON string to decode.
    /// - Returns: A tuple containing the decoded value (if successful) and a Boolean indicating
    ///   whether the JSON was complete or had to be completed.
    /// - Throws: An error if the string cannot be decoded into the specified type.
    public func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> (
        value: T, isComplete: Bool
    ) {
        guard let data = string.data(using: .utf8) else {
            throw PartialJSONDecoderError.invalidUTF8Data
        }

        return try decode(type, from: data)
    }
}
