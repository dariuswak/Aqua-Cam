
import CoreBluetooth

struct BleConstants {

    static let peripherialName = "Kraken"

    static let deviceInformationServiceUuid = CBUUID(string: "180A")

    static let batteryServiceUuid = CBUUID(string: "180F")

    static let batteryLevelCharacteristicUuid = CBUUID(string: "2A19")

    static let emulatedBatteryServiceUuid = CBUUID(string: "82C01FB2-8551-4F8B-BC77-529F51041EBE") // 180F - The specified UUID is not allowed for this operation

    static let emulatedBatteryLevelCharacteristicUuid = CBUUID(string: "313E0498-7212-44E2-8353-FE0E6467445A") // 2A19 - The specified UUID is not allowed for this operation

    static let sensorsServiceUuid = CBUUID(string: "00001623-1212-EFDE-1523-785FEABCD123")

    static let sensorsCharacteristicUuid = CBUUID(string: "00001625-1212-EFDE-1523-785FEABCD123")

    static let buttonsServiceUuid = CBUUID(string: "00001523-1212-EFDE-1523-785FEABCD123")

    static let buttonsCharacteristicUuid = CBUUID(string: "00001524-1212-EFDE-1523-785FEABCD123")

    static let shutterButtonCode = Data([32])

    static let focusButtonCode = Data([97])

    static let focusPressHoldButtonCode = Data([96])

    static let modeButtonCode = Data([16])

    static let upButtonCode = Data([64])

    static let menuButtonCode = Data([48])

    static let downButtonCode = Data([80])

}
