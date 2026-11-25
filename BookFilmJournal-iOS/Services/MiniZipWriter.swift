import Foundation
import zlib

struct MiniZipWriter {
    private struct Entry {
        let name: String
        let crc: UInt32
        let size: Int
        let offset: Int
    }

    private var output = Data()
    private var entries: [Entry] = []

    mutating func add(_ name: String, data: Data) {
        let nameData = Data(name.utf8)
        let offset = output.count
        let crc = data.withUnsafeBytes { bytes -> UInt32 in
            guard let base = bytes.bindMemory(to: Bytef.self).baseAddress else { return 0 }
            return UInt32(crc32(0, base, uInt(data.count)))
        }
        let (time, date) = dosDateTime(Date())
        output.appendUInt32(0x04034b50)
        output.appendUInt16(20)
        output.appendUInt16(0x0800)
        output.appendUInt16(0)
        output.appendUInt16(time)
        output.appendUInt16(date)
        output.appendUInt32(crc)
        output.appendUInt32(UInt32(data.count))
        output.appendUInt32(UInt32(data.count))
        output.appendUInt16(UInt16(nameData.count))
        output.appendUInt16(0)
        output.append(nameData)
        output.append(data)
        entries.append(Entry(name: name, crc: crc, size: data.count, offset: offset))
    }

    func finalize() -> Data {
        let centralStart = output.count
        var central = Data()
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let (time, date) = dosDateTime(Date())
            central.appendUInt32(0x02014b50)
            central.appendUInt16(20)
            central.appendUInt16(20)
            central.appendUInt16(0x0800)
            central.appendUInt16(0)
            central.appendUInt16(time)
            central.appendUInt16(date)
            central.appendUInt32(entry.crc)
            central.appendUInt32(UInt32(entry.size))
            central.appendUInt32(UInt32(entry.size))
            central.appendUInt16(UInt16(nameData.count))
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(0)
            central.appendUInt32(UInt32(entry.offset))
            central.append(nameData)
        }
        var result = output
        result.append(central)
        result.appendUInt32(0x06054b50)
        result.appendUInt16(0)
        result.appendUInt16(0)
        result.appendUInt16(UInt16(entries.count))
        result.appendUInt16(UInt16(entries.count))
        result.appendUInt32(UInt32(central.count))
        result.appendUInt32(UInt32(centralStart))
        result.appendUInt16(0)
        return result
    }

    private func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let calendar = Calendar.current
        let year = max(1980, calendar.component(.year, from: date))
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date) / 2
        let time = UInt16((hour << 11) | (minute << 5) | second)
        let dateValue = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (time, dateValue)
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
