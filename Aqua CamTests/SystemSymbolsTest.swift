import XCTest
@testable import Aqua_Cam

final class SystemSymbolsTest: XCTestCase {

    func testSystemSymbolsShouldBeAvailable() throws {
        XCTAssertNotNil(UIImage.questionMarkCircle)

        XCTAssertNotNil(UIImage.battery0)
        XCTAssertNotNil(UIImage.battery25)
        XCTAssertNotNil(UIImage.battery50)
        XCTAssertNotNil(UIImage.battery75)
        XCTAssertNotNil(UIImage.battery100)

        XCTAssertNotNil(UIImage.sunMax)
        XCTAssertNotNil(UIImage.cloudSun)
        XCTAssertNotNil(UIImage.cloud)
        XCTAssertNotNil(UIImage.cloudHeavyRain)
        XCTAssertNotNil(UIImage.cloudBolt)
    }

}
