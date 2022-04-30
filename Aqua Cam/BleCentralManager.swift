import CoreBluetooth
import UIKit
import os

class BleCentralManager: NSObject {

    @objc var centralManager: CBCentralManager = CBCentralManager(delegate: nil, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])

    var discoveredPeripheral: CBPeripheral?

    func initiate() {
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    func connectToPeripheral() {
        let foundPeripherals: [CBPeripheral] = (centralManager.retrieveConnectedPeripherals(withServices: [BleConstants.buttonsServiceUuid]))
        if let foundPeripheral = foundPeripherals.last {
            os_log("Found previously connected peripherals with Buttons Service: \(foundPeripherals)")
            os_log("Connecting to peripheral \(foundPeripheral)")
			discoveredPeripheral = foundPeripheral
            centralManager.connect(foundPeripheral, options: nil)
        } else {
            centralManager.scanForPeripherals(withServices: nil, // Kraken housing doesn't advertise anything specific
                                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]) // required to receive RSSI updates
        }
    }

    private func cleanup() {
        guard let discoveredPeripheral = discoveredPeripheral,
            case .connected = discoveredPeripheral.state else { return }

        // unsubscribe from notifications
        discoveredPeripheral.services?.forEach({ service in
            service.characteristics?.forEach({ characteristic in
                if characteristic.isNotifying {
                    discoveredPeripheral.setNotifyValue(false, for: characteristic)
                }
            })
        })

        centralManager.cancelPeripheralConnection(discoveredPeripheral)
    }

}

extension BleCentralManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            os_log("CBManager: Bluetooth is powered on")
            connectToPeripheral()
        case .poweredOff, .resetting, .unsupported, .unknown:
            os_log("CBManager: Bluetooth is powered off or unavailable")
        case .unauthorized:
            os_log("CBManager: Bluetooth is denied permission")
        @unknown default:
            os_log("CBManager: A previously unknown state occurred")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {

        guard let advertisedServiceName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              advertisedServiceName == BleConstants.peripherialName
                else { return }

        // Reject if the signal strength is too low to attempt data transfer.
        // Change the minimum RSSI value depending on your app’s use case.
        guard RSSI.intValue > -40 else {
            os_log("Discovered perhiperal not in expected range, at %d", RSSI.intValue)
            return
        }
//        guard peripheral.name == "Kraken" else { return }
//        os_log("Discovered %s at %d", String(describing: peripheral.name), RSSI.intValue)
//        os_log("Discovered %s", String(describing: advertisementData))
//        os_log("%s == %s", String(describing: CBUUID(nsuuid: peripheral.identifier)), String(describing: TransferService.serviceUUID))
//        guard let advertisedServiceUuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? NSArray,
//              advertisedServiceUuids.contains(TransferService.serviceUUID)
//                else { return }

        // Device is in range - have we already seen it?
        if discoveredPeripheral != peripheral {
            os_log("Discovered %s/%s at %d", String(describing: peripheral.name),
                   String(describing: advertisementData[CBAdvertisementDataLocalNameKey]),
                   RSSI.intValue)

            // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it.
            discoveredPeripheral = peripheral

            // And finally, connect to the peripheral.
            os_log("Connecting to perhiperal %@", peripheral)
            centralManager.connect(peripheral, options: nil)
        }
    }

    /*
     *  If the connection fails for whatever reason, we need to deal with it.
     */
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        os_log("Failed to connect to %@. %s", peripheral, String(describing: error))
        cleanup()
    }

    /*
     *  We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
     */
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        os_log("Peripheral Connected")

        // Stop scanning
        centralManager.stopScan()
        os_log("Scanning stopped")

        // Make sure we get the discovery callbacks
        peripheral.delegate = self

        // Search only for services that match our UUID
//        peripheral.discoverServices(nil)
        peripheral.discoverServices([BleConstants.deviceInformationServiceUuid,
                                     BleConstants.batteryServiceUuid, BleConstants.emulatedBatteryServiceUuid,
                                     BleConstants.sensorsServiceUuid,
                                     BleConstants.buttonsServiceUuid])
    }

    /*
     *  Once the disconnection happens, we need to clean up our local copy of the peripheral
     */
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        os_log("Perhiperal Disconnected")
        discoveredPeripheral = nil

        // We're disconnected, so start scanning again
        connectToPeripheral()
    }

}

extension BleCentralManager: CBPeripheralDelegate {
    // implementations of the CBPeripheralDelegate methods

    /*
     *  The peripheral letting us know when services have been invalidated.
     */
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {

        os_log("Transfer service is invalidated - rediscover services")
        cleanup()
//        for service in invalidatedServices where service.uuid == TransferService.serviceUuid {
//            os_log("Transfer service is invalidated - rediscover services")
//            peripheral.discoverServices([TransferService.serviceUuid])
//        }
    }

    /*
     *  The Transfer Service was discovered
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            os_log("Error discovering services: %s", error.localizedDescription)
            cleanup()
            return
        }

        // Discover the characteristic we want...

        // Loop through the newly filled peripheral.services array, just in case there's more than one.
        guard let peripheralServices = peripheral.services else { return }
        for service in peripheralServices {
            os_log("Discovered services: %@", service)
            peripheral.discoverCharacteristics(nil, for: service)
//            peripheral.discoverCharacteristics([TransferService.buttonsCharacteristicUuid,
//                                                TransferService.sensorsCharacteristicUuid
//                                               ], for: service)
        }
    }

    /*
     *  The Transfer characteristic was discovered.
     *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Deal with errors (if any).
        if let error = error {
            os_log("Error discovering characteristics: %s", error.localizedDescription)
            cleanup()
            return
        }
        os_log("Discovered characteristics: %@", service.characteristics!)
        // Again, we loop through the array, just in case and check if it's the right one
        guard let serviceCharacteristics = service.characteristics else { return }
        for characteristic in serviceCharacteristics
        //where characteristic.uuid == TransferService.characteristicUUID
        {
            if (characteristic.properties.contains(.notify)) {
                os_log("The characteristic %@ sends notifications, subscribing.",  characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            } // else // subscription request will conflict with read request
            if (characteristic.properties.contains(.read)) {
                os_log("The characteristic %@ can be read, sending read request.",  characteristic)
                peripheral.readValue(for: characteristic)
            }
            os_log("Wait for %@", characteristic)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                os_log("Service %s - Characteristic: %@", service.uuid.uuidString, characteristic)
            }
        }

        // Once this is complete, we just need to wait for the data to come in.
    }

    /*
     *   This callback lets us know more data has arrived via notification on the characteristic
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Deal with errors (if any)
        if let error = error {
            os_log("Error discovering characteristics: %s", error.localizedDescription)
            cleanup()
            return
        }

        var bytes: [UInt8] = []
        characteristic.value?.withUnsafeBytes{$0.forEach{bytes.append($0)}}
        let stringForm = String(bytes: characteristic.value ?? Data([]), encoding: .utf8)!
        os_log("Peripheral \(peripheral.identifier.uuidString) - Characteristic \(characteristic.uuid.uuidString): \(bytes) \(stringForm)")

//        // Have we received the end-of-message token?
//        if stringFromData == "EOM" {
//            // End-of-message case: show the data.
//            // Dispatch the text view update to the main queue for updating the UI, because
//            // we don't know which thread this method will be called back on.
//            DispatchQueue.main.async() {
//                self.textView.text = String(data: self.data, encoding: .utf8)
//            }
//
//            // Write test data
//            writeData()
//        } else {
//            // Otherwise, just append the data to what we have previously received.
//            data.append(characteristicData)
//        }
    }

    /*
     *  The peripheral letting us know whether our subscribe/unsubscribe happened or not
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        // Deal with errors (if any)
        if let error = error {
            os_log("Error changing notification state: %s", error.localizedDescription)
            return
        }

        // Exit if it's not the transfer characteristic
        //guard characteristic.uuid == TransferService.characteristicUUID else { return }

        if characteristic.isNotifying {
            // Notification has started
            os_log("Notification began on %@", characteristic)
        } else {
            // Notification has stopped, so disconnect from the peripheral
            os_log("Notification stopped on %@. Disconnecting", characteristic)
            cleanup()
        }

    }

}

