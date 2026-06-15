import Foundation
import CryptoKit

/// C4 ID content hash (used in ASC MHL chain files). A C4 ID is the SHA-512 of the
/// content, base58-encoded (Bitcoin alphabet) and left-padded to 88 chars, prefixed
/// with "c4" — 90 chars total.
enum C4Hash {
    private static let charset = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    static func id(of data: Data) -> String {
        let digest = Array(SHA512.hash(data: data))   // 64 bytes, big-endian
        var encoded = base58(digest)
        if encoded.count < 88 {
            encoded = String(repeating: "1", count: 88 - encoded.count) + encoded
        }
        return "c4" + encoded
    }

    private static func base58(_ bytes: [UInt8]) -> String {
        // Convert the big-endian byte array to base58 digits.
        var digits: [Int] = [0]
        for b in bytes {
            var carry = Int(b)
            for i in 0..<digits.count {
                carry += digits[i] << 8
                digits[i] = carry % 58
                carry /= 58
            }
            while carry > 0 {
                digits.append(carry % 58)
                carry /= 58
            }
        }
        return String(digits.reversed().map { charset[$0] })
    }
}
