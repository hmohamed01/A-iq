import XCTest
@testable import A_IQ

final class MetadataAnalyzerTests: XCTestCase {

    // MARK: - AI Software Detection Tests

    func testIsAISoftwareDALLE() {
        XCTAssertTrue(MetadataResult.isAISoftware("DALL-E 3"))
        XCTAssertTrue(MetadataResult.isAISoftware("DALL·E"))
        XCTAssertTrue(MetadataResult.isAISoftware("dall-e"))
    }

    func testIsAISoftwareMidjourney() {
        XCTAssertTrue(MetadataResult.isAISoftware("Midjourney"))
        XCTAssertTrue(MetadataResult.isAISoftware("midjourney v5"))
    }

    func testIsAISoftwareStableDiffusion() {
        XCTAssertTrue(MetadataResult.isAISoftware("Stable Diffusion"))
        XCTAssertTrue(MetadataResult.isAISoftware("stable diffusion xl"))
    }

    func testIsAISoftwareAdobeFirefly() {
        XCTAssertTrue(MetadataResult.isAISoftware("Adobe Firefly"))
        XCTAssertTrue(MetadataResult.isAISoftware("Photoshop Generative Fill"))
    }

    func testIsAISoftwareNormalSoftware() {
        XCTAssertFalse(MetadataResult.isAISoftware("Adobe Photoshop CC 2024"))
        XCTAssertFalse(MetadataResult.isAISoftware("Adobe Lightroom Classic"))
        XCTAssertFalse(MetadataResult.isAISoftware("Canon DPP"))
        XCTAssertFalse(MetadataResult.isAISoftware("Capture One"))
    }

    // MARK: - Metadata Result Creation Tests

    func testMetadataResultWithCameraInfo() {
        let result = MetadataResult(
            hasExifData: true,
            cameraInfo: CameraInfo(
                make: "Canon",
                model: "EOS R5",
                lens: "RF 24-70mm f/2.8L",
                focalLength: "50mm",
                aperture: "f/2.8",
                iso: "400",
                shutterSpeed: "1/250"
            ),
            isJPEG: true
        )

        XCTAssertTrue(result.hasExifData)
        XCTAssertNotNil(result.cameraInfo)
        XCTAssertEqual(result.cameraInfo?.make, "Canon")
        XCTAssertEqual(result.cameraInfo?.model, "EOS R5")
        XCTAssertLessThan(result.score, 0.5) // Camera info suggests authentic
        XCTAssertEqual(result.confidence, .high)
    }

    func testMetadataResultWithGPS() {
        let result = MetadataResult(
            hasExifData: true,
            gpsLocation: GPSLocation(latitude: 37.7749, longitude: -122.4194),
            isJPEG: true
        )

        XCTAssertNotNil(result.gpsLocation)
        if let location = result.gpsLocation {
            XCTAssertEqual(location.latitude, 37.7749, accuracy: 0.0001)
            XCTAssertEqual(location.longitude, -122.4194, accuracy: 0.0001)
        }
    }

    func testMetadataResultWithAISoftware() {
        let result = MetadataResult(
            hasExifData: true,
            softwareInfo: "DALL-E 3",
            isJPEG: true
        )

        // AI software detected increases score significantly
        XCTAssertGreaterThan(result.score, 0.5)
        // Evidence should include AI software detection
        XCTAssertTrue(result.evidence.contains { $0.type == .metadataAISoftware })
    }

    func testMetadataResultMissingEXIF() {
        let result = MetadataResult(
            hasExifData: false,
            isJPEG: true
        )

        XCTAssertFalse(result.hasExifData)
        // Missing EXIF in JPEG results in elevated score
        XCTAssertGreaterThan(result.score, 0.5)
        // Evidence should indicate missing metadata
        XCTAssertTrue(result.evidence.contains { $0.type == .metadataAbsent })
    }

    func testMetadataResultMissingEXIFNonJPEG() {
        let result = MetadataResult(
            hasExifData: false,
            isJPEG: false // PNG for example
        )

        // Missing EXIF in non-JPEG is normal
        XCTAssertFalse(result.anomalies.contains { $0.type == .missingExif })
    }

    // MARK: - Anomaly Tests

    func testAnomalyTypeMappings() {
        XCTAssertEqual(AnomalyType.missingExif.toEvidenceType(), .metadataAbsent)
        XCTAssertEqual(AnomalyType.aiToolDetected.toEvidenceType(), .metadataAISoftware)
        XCTAssertEqual(AnomalyType.futureDateDetected.toEvidenceType(), .metadataDateAnomaly)
        XCTAssertEqual(AnomalyType.impossibleDate.toEvidenceType(), .metadataDateAnomaly)
        XCTAssertEqual(AnomalyType.inconsistentTimestamps.toEvidenceType(), .metadataAnomaly)
    }

    // MARK: - GPS Location Tests

    func testGPSLocationCoordinate() {
        let location = GPSLocation(latitude: 37.7749, longitude: -122.4194, altitude: 10.0)

        let coordinate = location.coordinate
        XCTAssertEqual(coordinate.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(coordinate.longitude, -122.4194, accuracy: 0.0001)
    }

    // MARK: - Camera Info Tests

    func testCameraInfoFullDetails() {
        let camera = CameraInfo(
            make: "Sony",
            model: "A7 IV",
            lens: "FE 24-70mm f/2.8 GM",
            focalLength: "35mm",
            aperture: "f/4.0",
            iso: "800",
            shutterSpeed: "1/125"
        )

        XCTAssertEqual(camera.make, "Sony")
        XCTAssertEqual(camera.model, "A7 IV")
        XCTAssertEqual(camera.lens, "FE 24-70mm f/2.8 GM")
        XCTAssertEqual(camera.focalLength, "35mm")
        XCTAssertEqual(camera.aperture, "f/4.0")
        XCTAssertEqual(camera.iso, "800")
        XCTAssertEqual(camera.shutterSpeed, "1/125")
    }

    func testCameraInfoMinimalDetails() {
        let camera = CameraInfo(make: "Apple", model: "iPhone 15 Pro")

        XCTAssertEqual(camera.make, "Apple")
        XCTAssertEqual(camera.model, "iPhone 15 Pro")
        XCTAssertNil(camera.lens)
        XCTAssertNil(camera.focalLength)
    }
}
