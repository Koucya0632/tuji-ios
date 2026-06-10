// Project-wide JSON codec config so all API call sites agree on date
// format etc.

import Foundation

extension JSONDecoder {
    static let tuji: JSONDecoder = {
        let d = JSONDecoder()
        // Backend emits camelCase already (Next.js helpers convert from
        // snake_case DB columns before serializing). Conversion is on as a
        // safety net for any snake_case payloads that slip through.
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let tuji: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
