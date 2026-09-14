import Foundation

/// Niimbot frame: 55 55 cmd len data… xor(cmd, len, data) aa aa
public struct Packet: Equatable, Sendable {
    public let cmd: UInt8
    public let data: Data

    public static func encode(_ cmd: UInt8, _ data: Data = Data([1])) -> Data {
        let chk = data.reduce(cmd ^ UInt8(data.count), ^)
        return Data([0x55, 0x55, cmd, UInt8(data.count)]) + data + Data([chk, 0xAA, 0xAA])
    }
}

/// Reassembles packets from BLE notifications, which may split or merge frames.
public struct PacketDecoder {
    private var buf: [UInt8] = []

    public init() {}

    public mutating func push(_ chunk: Data) -> [Packet] {
        buf += chunk
        var out: [Packet] = []
        while let start = buf.indices.dropLast().first(where: { buf[$0] == 0x55 && buf[$0 + 1] == 0x55 }),
              buf.count >= start + 4 {
            buf.removeFirst(start)
            let end = Int(buf[3]) + 7
            guard buf.count >= end else { break }
            let pkt = Packet(cmd: buf[2], data: Data(buf[4..<end - 3]))
            if Packet.encode(pkt.cmd, pkt.data) == Data(buf[..<end]) { out.append(pkt) }
            buf.removeFirst(end)
        }
        return out
    }
}

func u16(_ n: Int) -> Data { Data([UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)]) }
