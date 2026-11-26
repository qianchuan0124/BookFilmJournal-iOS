import Foundation
import zlib

struct MiniZipEntry {
    let name: String
    let data: Data
}

enum MiniZipError: LocalizedError {
    case invalidArchive
    case unsupported(String)
    case inflatedSizeMismatch

    var errorDescription: String? {
        switch self {
        case .invalidArchive: L10n.Error.zipInvalid
        case .unsupported(let message): message
        case .inflatedSizeMismatch: L10n.Error.unzipFailed
        }
    }
}

enum MiniZip {
    static func entries(at url: URL, suffixes: [String], includeExtensionless: Bool = false) throws -> [MiniZipEntry] {
        let data = try Data(contentsOf: url)
        return try entries(in: data, suffixes: suffixes, includeExtensionless: includeExtensionless)
    }

    static func entries(in data: Data, suffixes: [String], includeExtensionless: Bool = false) throws -> [MiniZipEntry] {
        let bytes = [UInt8](data)
        guard let eocd = findEOCD(bytes) else { throw MiniZipError.invalidArchive }
        let count = Int(readUInt16(bytes, eocd + 10))
        let centralOffset = Int(readUInt32(bytes, eocd + 16))
        guard centralOffset >= 0, centralOffset < bytes.count else { throw MiniZipError.invalidArchive }

        var result: [MiniZipEntry] = []
        var cursor = centralOffset
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count,
                  readUInt32(bytes, cursor) == 0x02014b50 else {
                throw MiniZipError.invalidArchive
            }
            let flags = readUInt16(bytes, cursor + 8)
            let method = readUInt16(bytes, cursor + 10)
            let compressedSize = Int(readUInt32(bytes, cursor + 20))
            let uncompressedSize = Int(readUInt32(bytes, cursor + 24))
            let nameLength = Int(readUInt16(bytes, cursor + 28))
            let extraLength = Int(readUInt16(bytes, cursor + 30))
            let commentLength = Int(readUInt16(bytes, cursor + 32))
            let localOffset = Int(readUInt32(bytes, cursor + 42))
            guard cursor + 46 + nameLength <= bytes.count else { throw MiniZipError.invalidArchive }
            let nameData = Data(bytes[cursor + 46 ..< cursor + 46 + nameLength])
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""

            let lower = name.lowercased()
            let fileName = (name as NSString).lastPathComponent
            let extensionless = !name.hasSuffix("/") && !fileName.isEmpty
                && (fileName as NSString).pathExtension.isEmpty
            if suffixes.contains(where: { lower.hasSuffix($0) })
                || (includeExtensionless && extensionless) {
                let content = try extract(
                    bytes: bytes,
                    localOffset: localOffset,
                    method: method,
                    flags: flags,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize
                )
                result.append(MiniZipEntry(name: name, data: content))
            }
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    private static func extract(
        bytes: [UInt8],
        localOffset: Int,
        method: UInt16,
        flags: UInt16,
        compressedSize: Int,
        uncompressedSize: Int
    ) throws -> Data {
        guard localOffset + 30 <= bytes.count,
              readUInt32(bytes, localOffset) == 0x04034b50 else {
            throw MiniZipError.invalidArchive
        }
        guard flags & 0x0001 == 0 else { throw MiniZipError.unsupported(L10n.Error.encryptedArchive) }
        let nameLength = Int(readUInt16(bytes, localOffset + 26))
        let extraLength = Int(readUInt16(bytes, localOffset + 28))
        let start = localOffset + 30 + nameLength + extraLength
        guard start >= 0, start + compressedSize <= bytes.count else { throw MiniZipError.invalidArchive }
        let payload = Data(bytes[start ..< start + compressedSize])

        switch method {
        case 0:
            return payload
        case 8:
            return try inflateRaw(payload, expectedSize: uncompressedSize)
        default:
            throw MiniZipError.unsupported(L10n.Error.compressionMethod(String(describing: method)))
        }
    }

    private static func inflateRaw(_ data: Data, expectedSize: Int) throws -> Data {
        var stream = z_stream()
        let initResult = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else { throw MiniZipError.inflatedSizeMismatch }
        defer { inflateEnd(&stream) }

        let capacity = max(expectedSize, max(data.count * 4, 1 << 20))
        var output = [UInt8](repeating: 0, count: capacity)
        var produced = 0
        let status: Int32 = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { out in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = out.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(out.count)
                let value = inflate(&stream, Z_FINISH)
                produced = Int(stream.total_out)
                return value
            }
        }
        guard status == Z_STREAM_END else { throw MiniZipError.inflatedSizeMismatch }
        guard produced <= output.count else { throw MiniZipError.inflatedSizeMismatch }
        return Data(output.prefix(produced))
    }

    private static func findEOCD(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lower = max(0, bytes.count - 65_557)
        var index = bytes.count - 22
        while index >= lower {
            if readUInt32(bytes, index) == 0x06054b50 { return index }
            index -= 1
        }
        return nil
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
