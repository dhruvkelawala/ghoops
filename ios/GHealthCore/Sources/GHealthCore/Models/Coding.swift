import Foundation

public enum JSONCoding {
    private static let plainTime = Date.ISO8601FormatStyle()
    private static let fractionalTime = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? plainTime.parse(text) { return date }
            if let date = try? fractionalTime.parse(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid RFC 3339 time")) // goop-lint: allow enginenumber: standard name
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

@propertyWrapper
public struct DefaultEmpty<Element: Codable & Sendable>: Codable, Sendable {
    public var wrappedValue: [Element]
    public init(wrappedValue: [Element]) { self.wrappedValue = wrappedValue }
    public init(from decoder: any Decoder) throws {
        self.wrappedValue = try decoder.singleValueContainer().decode([Element].self)
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    public func decode<T>(_ type: DefaultEmpty<T>.Type, forKey key: Key) throws -> DefaultEmpty<T> {
        try decodeIfPresent(type, forKey: key) ?? DefaultEmpty(wrappedValue: [])
    }
}
