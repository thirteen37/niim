import CoreBluetooth
import Foundation
import Observation

public struct NiimError: LocalizedError {
    public let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private let serviceUUID = CBUUID(string: "e7810a71-73ae-499d-8c15-faa9aef0c3f2")

// request cmd -> response cmd (PrinterInfo 0x40 replies 0x40 + info type)
private let responses: [UInt8: UInt8] = [0xC1: 0xC2, 0x21: 0x31, 0x23: 0x33, 0x01: 0x02, 0x20: 0x30, 0x03: 0x04,
                                         0x13: 0x14, 0x15: 0x16, 0xE3: 0xE4, 0xA3: 0xB3, 0xF3: 0xF4, 0x1A: 0x1B]

/// D110 over BLE. Print sequence = niimbluelib's D110PrintTask, verified with niim.py.
@Observable @MainActor
public final class Printer: NSObject {
    public private(set) var status = "Disconnected"
    public private(set) var isReady = false
    public private(set) var isBusy = false
    public private(set) var rfid: Rfid?
    public private(set) var label: LabelSpec?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var char: CBCharacteristic?
    @ObservationIgnored private var decoder = PacketDecoder()
    @ObservationIgnored private var waiter: (id: Int, want: UInt8, cont: CheckedContinuation<Data, Error>)?
    @ObservationIgnored private var nextID = 0

    public override init() { super.init() }

    public func connect() {
        status = "Searching…"
        if let central {
            if central.state == .poweredOn { central.scanForPeripherals(withServices: nil) }
        } else {
            central = CBCentralManager(delegate: self, queue: nil)  // scans once powered on
        }
    }

    public func printLabel(_ bmp: Bitmap, density: Int = 2) async throws {
        guard let peripheral, let char else { throw NiimError("Not connected") }
        isBusy = true
        defer { isBusy = false }
        _ = try await send(0xC1)  // connect
        _ = try await send(0x21, Data([UInt8(density)]))  // 1-3
        _ = try await send(0x23, Data([1]))  // label type: with gaps
        _ = try await send(0x01)  // print start
        _ = try await send(0x20)  // print clear
        _ = try await send(0x03)  // page start
        _ = try await send(0x13, u16(bmp.height) + u16(bmp.width))
        _ = try await send(0x15, u16(1))  // quantity
        for pkt in bmp.rowPackets() {
            // ponytail: fixed 10ms pacing like niimbluelib; use canSendWriteWithoutResponse if rows drop
            peripheral.writeValue(pkt, for: char, type: .withoutResponse)
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try await send(0xE3)  // page end
        for _ in 0..<100 {  // status: page u16, print %, feed %, error @8
            let s = [UInt8](try await send(0xA3))
            if s.count == 10, s[8] != 0 { throw NiimError("Printer error 0x\(String(s[8], radix: 16))") }
            if s.count >= 4, Int(s[0]) << 8 | Int(s[1]) >= 1, s[2] == 100, s[3] == 100 { break }
            try await Task.sleep(for: .milliseconds(300))
        }
        _ = try await send(0xF3)  // print end
    }

    private func send(_ cmd: UInt8, _ data: Data = Data([1])) async throws -> Data {
        guard let peripheral, let char else { throw NiimError("Not connected") }
        let want = cmd == 0x40 ? 0x40 &+ data[data.startIndex] : responses[cmd]!
        return try await withCheckedThrowingContinuation { cont in
            nextID += 1
            let id = nextID
            waiter = (id, want, cont)
            peripheral.writeValue(Packet.encode(cmd, data), for: char, type: .withoutResponse)
            Task {
                try? await Task.sleep(for: .seconds(3))
                if waiter?.id == id { fail(NiimError("No reply to 0x\(String(cmd, radix: 16))")) }
            }
        }
    }

    private func receive(_ chunk: Data) {
        for pkt in decoder.push(chunk) {
            guard let w = waiter else { continue }
            if pkt.cmd == w.want {
                waiter = nil
                w.cont.resume(returning: pkt.data)
            } else if pkt.cmd == 0x00 || pkt.cmd == 0xDB {  // not supported / print error; others (0xd3 check line) skipped
                fail(NiimError("Printer rejected command (0x\(String(pkt.cmd, radix: 16)) \(pkt.data.map { String(format: "%02x", $0) }.joined()))"))
            }
        }
    }

    private func fail(_ error: Error) {
        let w = waiter
        waiter = nil
        w?.cont.resume(throwing: error)
    }

    private func loadInfo() async {
        do {
            rfid = Rfid(try await send(0x1A))
            isReady = true
            status = "Connected"
            if let rfid { label = try await LabelSpec.lookup(barcode: rfid.barcode) }
        } catch {
            status = error.localizedDescription
        }
    }

    private func disconnected(_ message: String) {
        peripheral = nil
        char = nil
        isReady = false
        status = message
        fail(NiimError(message))
    }
}

extension Printer: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state == .poweredOn { central.scanForPeripherals(withServices: nil) } else { status = "Bluetooth unavailable" }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                                           advertisementData: [String: Any], rssi: NSNumber) {
        guard p.name?.hasPrefix("D110") == true else { return }
        MainActor.assumeIsolated {
            central.stopScan()
            peripheral = p
            p.delegate = self
            status = "Connecting to \(p.name ?? "D110")…"
            central.connect(p)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([serviceUUID])
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { disconnected("Couldn't connect") }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { disconnected("Disconnected") }
    }

    nonisolated public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
    }

    nonisolated public func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let ch = s.characteristics?.first(where: { $0.properties.isSuperset(of: [.notify, .writeWithoutResponse]) }) else { return }
        MainActor.assumeIsolated { char = ch }
        p.setNotifyValue(true, for: ch)
    }

    nonisolated public func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated { _ = Task { await loadInfo() } }
    }

    nonisolated public func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let value = ch.value else { return }
        MainActor.assumeIsolated { receive(value) }
    }
}
