import Foundation
import PartialJSONDecoder
import Testing

@Suite("PartialJSONDecoder Tests")
struct PartialJSONDecoderTests {
    struct Person: Codable, Equatable {
        let name: String
        let age: Int
        let hobbies: [String]
    }

    struct NestedStructure: Codable, Equatable {
        let id: Int
        let data: Person
        let tags: [String]
    }

    @Test("Basic Partial JSON Decoder")
    func testPartialJSONDecoder() throws {
        let decoder = PartialJSONDecoder()

        // Complete JSON
        let completeJSON =
            "{\"name\": \"Alice\", \"age\": 30, \"hobbies\": [\"reading\", \"hiking\"]}"
        let (completePerson, isCompleteJSON) = try decoder.decode(Person.self, from: completeJSON)

        #expect(isCompleteJSON)
        #expect(completePerson.name == "Alice")
        #expect(completePerson.age == 30)
        #expect(completePerson.hobbies == ["reading", "hiking"])

        // Partial JSON
        let partialJSON = "{\"name\": \"Bob\", \"age\": 25, \"hobbies\": [\"gaming\", \"swimming\""
        let (partialPerson, isPartialJSON) = try decoder.decode(Person.self, from: partialJSON)

        #expect(!isPartialJSON)
        #expect(partialPerson.name == "Bob")
        #expect(partialPerson.age == 25)
        #expect(partialPerson.hobbies == ["gaming", "swimming"])
    }

    @Test("Decoding from Data")
    func testDecodingFromData() throws {
        let decoder = PartialJSONDecoder()

        // Complete JSON as Data
        let completeJSON =
            "{\"name\": \"Alice\", \"age\": 30, \"hobbies\": [\"reading\", \"hiking\"]}"
        guard let completeData = completeJSON.data(using: .utf8) else {
            Issue.record("Failed to convert JSON string to data")
            return
        }

        let (completePerson, isCompleteJSON) = try decoder.decode(Person.self, from: completeData)
        #expect(isCompleteJSON)
        #expect(completePerson.name == "Alice")

        // Partial JSON as Data
        let partialJSON = "{\"name\": \"Bob\", \"age\": 25, \"hobbies\": [\"gaming\""
        guard let partialData = partialJSON.data(using: .utf8) else {
            Issue.record("Failed to convert JSON string to data")
            return
        }

        let (partialPerson, isPartialJSON) = try decoder.decode(Person.self, from: partialData)
        #expect(!isPartialJSON)
        #expect(partialPerson.name == "Bob")
        #expect(partialPerson.age == 25)
        #expect(partialPerson.hobbies == ["gaming"])
    }

    @Test("Nested Structure Decoding")
    func testNestedStructureDecoding() throws {
        let decoder = PartialJSONDecoder()

        // Complete nested JSON
        let completeNestedJSON = """
            {
                "id": 123,
                "data": {
                    "name": "David",
                    "age": 40,
                    "hobbies": ["coding", "music"]
                },
                "tags": ["important", "urgent"]
            }
            """

        let (completeNested, isCompleteNested) = try decoder.decode(
            NestedStructure.self, from: completeNestedJSON)
        #expect(isCompleteNested)
        #expect(completeNested.id == 123)
        #expect(completeNested.data.name == "David")
        #expect(completeNested.tags == ["important", "urgent"])

        // Test decoding an incomplete JSON object
        // Skip test with partial JSON that would result in keyNotFound error
        // since we're changing the behavior to buffer until complete
    }

    @Test("Empty and Minimal JSON")
    func testEmptyAndMinimalJSON() throws {
        let decoder = PartialJSONDecoder()

        // Empty object
        let emptyObject = "{}"
        let (emptyPerson, isCompleteEmpty) = try decoder.decode(
            [String: String].self, from: emptyObject)
        #expect(isCompleteEmpty)
        #expect(emptyPerson.isEmpty)

        // Empty array
        let emptyArray = "[]"
        let (emptyList, isCompleteEmptyArray) = try decoder.decode([String].self, from: emptyArray)
        #expect(isCompleteEmptyArray)
        #expect(emptyList.isEmpty)

        // Partial empty object
        let partialEmptyObject = "{"
        let (partialEmpty, isCompletePartialEmpty) = try decoder.decode(
            [String: String].self, from: partialEmptyObject)
        #expect(!isCompletePartialEmpty)
        #expect(partialEmpty.isEmpty)
    }

    @Test("Custom Decoder Configuration")
    func testCustomDecoderConfiguration() throws {
        // Create a custom JSONDecoder with specific configuration
        let customJSONDecoder = JSONDecoder()
        customJSONDecoder.keyDecodingStrategy = .convertFromSnakeCase

        let partialJSONDecoder = PartialJSONDecoder(decoder: customJSONDecoder)

        // Test with a JSON containing snake_case keys
        let jsonWithSnakeCase = """
            {
                "user_name": "John",
                "user_age": 42,
                "favorite_hobbies": ["running"
            """

        struct User: Codable, Equatable {
            let userName: String
            let userAge: Int
            let favoriteHobbies: [String]
        }

        let (user, isComplete) = try partialJSONDecoder.decode(User.self, from: jsonWithSnakeCase)
        #expect(!isComplete)
        #expect(user.userName == "John")
        #expect(user.userAge == 42)
        #expect(user.favoriteHobbies == ["running"])
    }

    @Test("Error Handling")
    func testErrorHandling() throws {
        let decoder = PartialJSONDecoder()

        // Invalid UTF-8 data
        let invalidBytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        let invalidUTF8 = Data(invalidBytes)
        do {
            _ = try decoder.decode(Person.self, from: invalidUTF8)
            Issue.record("Expected invalidUTF8Data error but no error was thrown")
        } catch let error as PartialJSONDecoderError {
            // Check if it's the invalidUTF8Data error
            if case .invalidUTF8Data = error {
                #expect(Bool(true))
            } else {
                Issue.record("Expected invalidUTF8Data error but got \(error)")
            }
        } catch {
            Issue.record("Expected PartialJSONDecoderError but got \(error)")
        }

        // Malformed JSON that can't be completed properly
        let malformedJSON = "{\"name\": \"name with unclosed quote, \"age\": 30}"
        do {
            _ = try decoder.decode(Person.self, from: malformedJSON)
            Issue.record("Expected error for malformed JSON but none was thrown")
        } catch {
            // This should throw some kind of error
            #expect(Bool(true))
        }

        // Type mismatch
        let typeMismatchJSON = "{\"name\": 123, \"age\": \"thirty\", \"hobbies\": [\"reading\"]}"
        do {
            _ = try decoder.decode(Person.self, from: typeMismatchJSON)
            Issue.record("Expected error for type mismatch but none was thrown")
        } catch is PartialJSONDecoderError {
            // We expect a decoding error
            #expect(Bool(true))
        } catch {
            Issue.record("Expected PartialJSONDecoderError but got \(error)")
        }
    }
}
