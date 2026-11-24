import CoreBluetooth
import Foundation
import GHealthCore

@MainActor final class BluetoothHeartRateSource: NSObject, HeartRateSource, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private(set) var state: HeartRateConnection = .searching { didSet { onState?(state) } }
    var onSample: ((HeartRateSample) -> Void)?
    var onState: ((HeartRateConnection) -> Void)?
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var active = false
    private var discovery: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private let defaults = UserDefaults(suiteName: SharedAppGroup.id)!
    private let service = CBUUID(string: "180D")
    private let measurement = CBUUID(string: "2A37")

    func start() {
        guard !active else { return }
        active = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: "io.ghealth.app.hr"])
        } else { scan() }
    }
    func stop() {
        active = false; discovery?.cancel(); discovery = nil; timeout?.cancel(); timeout = nil; central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil; peripherals = [:]
    }
    func connect(id: UUID) {
        guard active, let found = peripherals[id], central?.state == .poweredOn else { return }
        discovery?.cancel(); central?.stopScan(); peripheral = found
        found.delegate = self; central?.connect(found)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard active else { return }
        switch central.state {
        case .poweredOn: scan()
        case .unauthorized: state = .denied
        case .poweredOff, .unsupported: state = .poweredOff
        default: state = .searching
        }
    }
    private func scan() {
        guard active, let central else { return }
        guard central.state == .poweredOn else {
            if central.state == .unauthorized { state = .denied }
            else if central.state == .poweredOff || central.state == .unsupported { state = .poweredOff }
            return
        }
        if let peripheral, peripheral.state == .connected { return }
        state = .searching; peripherals = [:]; discovery?.cancel(); discovery = nil
        central.scanForPeripherals(withServices: [service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.active else { return }
            if case .searching = self.state { self.state = .notFound }
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard active else { return }
        peripherals[peripheral.identifier] = peripheral
        if defaults.string(forKey: "goop.hr.peripheral") == peripheral.identifier.uuidString { connect(id: peripheral.identifier); return }
        if peripherals.count > 1 {
            discovery?.cancel()
            state = .choosing(peripherals.values.map { HeartRateDevice(id: $0.identifier, name: $0.name ?? "Heart rate monitor") }.sorted { $0.name < $1.name })
        } else if discovery == nil {
            discovery = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, self.peripherals.count == 1, let id = self.peripherals.keys.first else { return }
                self.connect(id: id)
            }
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard active else { central.cancelPeripheralConnection(peripheral); return }
        self.peripheral = peripheral; peripheral.delegate = self
        defaults.set(peripheral.identifier.uuidString, forKey: "goop.hr.peripheral")
        peripheral.discoverServices([service])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        self.peripheral = nil; discovery = nil; if active { scan() }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        guard active else { return }
        state = .searching; central.connect(peripheral)
    }
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first else { return }
        peripheral = restored; restored.delegate = self; peripherals[restored.identifier] = restored
        if active, restored.state == .connected { restored.discoverServices([service]) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard active else { return }
        for found in peripheral.services ?? [] where found.uuid == service { peripheral.discoverCharacteristics([measurement], for: found) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard active else { return }
        for found in service.characteristics ?? [] where found.uuid == measurement { peripheral.setNotifyValue(true, for: found) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard active, error == nil, characteristic.uuid == measurement, let data = characteristic.value, let bpm = HeartRateMeasurement.parse(data) else { return }
        state = .connected(peripheral.name ?? "Heart rate monitor", bpm)
        onSample?(HeartRateSample(t: .now, bpm: Double(bpm)))
    }
}
