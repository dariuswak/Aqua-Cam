import CoreBluetooth
import UIKit
import os

class BleCentralManager: NSObject {

    @objc var centralManager: CBCentralManager = CBCentralManager(delegate: nil, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])

    @objc dynamic var discoveredPeripheral: CBPeripheral?

    @objc dynamic var buttonPressed: UInt8 = 0

    @objc dynamic var depthSensor: Float = 0.0

    @objc dynamic var temperatureSensor: Float = 0.0

    @objc dynamic var batteryLevelPercentage: Int = 0

    func initiate() {
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    func initiateConnectionToPeripheral() {
        var foundPeripherals: [CBPeripheral]
        if let discoveredPeripheral = discoveredPeripheral {
            foundPeripherals = centralManager.retrievePeripherals(withIdentifiers: [discoveredPeripheral.identifier])
            if let foundPeripheral = foundPeripherals.last {
                os_log("Found previously connected peripherals: \(foundPeripherals)")
                os_log("Connecting to peripheral \(foundPeripheral)")
                centralManager.connect(foundPeripheral)
                return
            }
        }
        foundPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [BleConstants.buttonsServiceUuid])
        if let foundPeripheral = foundPeripherals.last {
            os_log("Found already connected peripherals: \(foundPeripherals)")
            os_log("Connecting to peripheral \(foundPeripheral)")
            discoveredPeripheral = foundPeripheral
            centralManager.connect(foundPeripheral)
            return
        }
        centralManager.scanForPeripherals(withServices: nil, // Kraken housing doesn't advertise anything specific
                                               options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]) // required to receive RSSI updates
    }

    private func cleanup() {
        guard let discoveredPeripheral = discoveredPeripheral,
              discoveredPeripheral.state == .connected else { return }

        // unsubscribe from notifications
        discoveredPeripheral.services?.forEach { service in
            service.characteristics?.forEach { characteristic in
                if characteristic.isNotifying {
                    discoveredPeripheral.setNotifyValue(false, for: characteristic)
                }
            }
        }

        centralManager.cancelPeripheralConnection(discoveredPeripheral)
        initiateConnectionToPeripheral()
    }

}

extension BleCentralManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            os_log("centralManager: Bluetooth is powered on")
            initiateConnectionToPeripheral()
        case .poweredOff, .resetting, .unsupported, .unknown:
            os_log("centralManager: Bluetooth is powered off or unavailable")
        case .unauthorized:
            os_log("centralManager: Bluetooth is denied permission")
        @unknown default:
            os_log("centralManager: A previously unknown state occurred")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let advertisedServiceName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              advertisedServiceName == BleConstants.peripherialName
                else { return }
        if discoveredPeripheral == peripheral {
            // already connecting to
            return
        }
        guard RSSI.intValue > BleConstants.connectableSignalStrengthThreshold else {
            os_log("Discovered perhiperal not in expected range, at \(RSSI.intValue)")
            return
        }
        os_log("""
               Connecting to discovered \(String(describing: peripheral.name)) \
               /\(String(describing: advertisementData[CBAdvertisementDataLocalNameKey]))
               """)
        centralManager.connect(peripheral)
        discoveredPeripheral = peripheral
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        os_log("Failed to connect to \(peripheral) \(String(describing: error))")
        cleanup()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        os_log("Peripheral Connected")
        centralManager.stopScan()
        os_log("Scanning stopped")
        peripheral.delegate = self
        peripheral.discoverServices([BleConstants.deviceInformationServiceUuid,
                                     BleConstants.batteryServiceUuid, BleConstants.emulatedBatteryServiceUuid,
                                     BleConstants.sensorsServiceUuid,
                                     BleConstants.buttonsServiceUuid])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        os_log("Perhiperal Disconnected, error (if any): \(String(describing: error))")
        initiateConnectionToPeripheral()
    }

}

extension BleCentralManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        os_log("Service invalidated - rediscover")
        cleanup()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            os_log("Error discovering services: \(String(describing: error))")
            cleanup()
            return
        }
        peripheral.services?.forEach { service in
            os_log("Discovered services: \(service)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            os_log("Error discovering characteristics for \(service): \(String(describing: error))")
            cleanup()
            return
        }
        service.characteristics?.forEach { characteristic in
            os_log("Discovered characteristic: \(characteristic)")
            if characteristic.properties.contains(.notify) {
                os_log("The characteristic \(characteristic) sends notifications, subscribing.")
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.read) {
                os_log("The characteristic \(characteristic) can be read, sending read request.")
                peripheral.readValue(for: characteristic)
            }
            os_log("Wait for \(characteristic)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                os_log("Service \(service.uuid.uuidString) - Characteristic: \(characteristic)")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            os_log("Error updating value for \(characteristic): \(String(describing: error))")
            cleanup()
            return
        }
        guard let value = characteristic.value, !value.isEmpty
                else { return }
        switch characteristic.uuid {
        case BleConstants.buttonsCharacteristicUuid:
            buttonPressed = value.first!
        case BleConstants.sensorsCharacteristicUuid:
            let sensorsValue = value.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
            let depthValue = Float(sensorsValue[0]) / 10.0
            let temperatureValue = Float(sensorsValue[1]) / 10.0
            // the housing transmits this continuously twice per second; avoid propagation of the redundant notifications
            if depthSensor != depthValue {
                depthSensor = depthValue
                Logger.log("depth", depthSensor)
            }
            if temperatureSensor != temperatureValue {
                temperatureSensor = temperatureValue
                Logger.log("temp", temperatureSensor)
            }
        case BleConstants.batteryLevelCharacteristicUuid, BleConstants.emulatedBatteryLevelCharacteristicUuid:
            batteryLevelPercentage = Int(value.first!)
            Logger.log("housing_battery", batteryLevelPercentage)
        default:
            let arrayValue = Array(value)
            let stringValue = String(bytes: value, encoding: .ascii)!
            os_log("Unhandled characteristic: \(characteristic.uuid.uuidString), value: \(arrayValue) <\(stringValue)>")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            os_log("Error changing notification state for \(characteristic): \(String(describing: error))")
            return
        }
        if characteristic.isNotifying {
            os_log("Notification began on \(characteristic)")
        } else {
            os_log("Notification stopped on \(characteristic). Disconnecting")
            cleanup()
        }
    }

}
