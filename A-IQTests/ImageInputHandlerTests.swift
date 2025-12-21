import XCTest
@testable import A_IQ

final class ImageInputHandlerTests: XCTestCase {

    // MARK: - Supported Extensions Tests

    func testSupportedExtensionsContainsJPEG() {
        XCTAssertTrue(ImageInputHandler.supportedExtensions.contains("jpg"))
        XCTAssertTrue(ImageInputHandler.supportedExtensions.contains("jpeg"))
    }

    func testSupportedExtensionsContainsPNG() {
        XCTAssertTrue(ImageInputHandler.supportedExtensions.contains("png"))
    }

    func testSupportedExtensionsContainsHEIC() {
        XCTAssertTrue(ImageInputHandler.supportedExtensions.contains("heic"))
        XCTAssertTrue(ImageInputHandler.supportedExtensions.contains("heif"))
    }

    func testSupportedExtensionsContainsWebP() {
        XCTAssertTrue(ImageInputHandler.supportedExtensions.contains("webp"))
    }

    func testSupportedExtensionsContainsTIFF() {
        XCTAssertTrue(ImageInputHandler.supportedExtensions.contains("tiff"))
        XCTAssertTrue(ImageInputHandler.supportedExtensions.contains("tif"))
    }

    func testSupportedExtensionsContainsAVIF() {
        XCTAssertTrue(ImageInputHandler.supportedExtensions.contains("avif"))
    }

    func testSupportedExtensionsDoesNotContainUnsupported() {
        XCTAssertFalse(ImageInputHandler.supportedExtensions.contains("gif"))
        XCTAssertFalse(ImageInputHandler.supportedExtensions.contains("bmp"))
        XCTAssertFalse(ImageInputHandler.supportedExtensions.contains("svg"))
        XCTAssertFalse(ImageInputHandler.supportedExtensions.contains("psd"))
    }

    // MARK: - File Size Tests

    func testMaxFileSizeIs100MB() {
        XCTAssertEqual(ImageInputHandler.maxFileSizeBytes, 100_000_000)
    }

    // MARK: - Image Input Error Tests

    func testUnsupportedFormatErrorDescription() {
        let error = ImageInputError.unsupportedFormat("gif")
        XCTAssertTrue(error.errorDescription?.contains("gif") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("JPEG") ?? false)
    }

    func testFileTooLargeErrorDescription() {
        let error = ImageInputError.fileTooLarge(150_000_000)
        XCTAssertNotNil(error.errorDescription)
    }

    func testFileNotFoundErrorDescription() {
        let error = ImageInputError.fileNotFound("/path/to/image.jpg")
        XCTAssertTrue(error.errorDescription?.contains("/path/to/image.jpg") ?? false)
    }

    func testFileNotReadableErrorDescription() {
        let error = ImageInputError.fileNotReadable("/path/to/image.jpg")
        XCTAssertTrue(error.errorDescription?.contains("/path/to/image.jpg") ?? false)
    }

    func testClipboardEmptyErrorDescription() {
        let error = ImageInputError.clipboardEmpty
        XCTAssertTrue(error.errorDescription?.contains("clipboard") ?? false)
    }

    func testInvalidImageDataErrorDescription() {
        let error = ImageInputError.invalidImageData
        XCTAssertTrue(error.errorDescription?.contains("Invalid") ?? false)
    }

    // MARK: - ImageSource Tests

    func testImageSourceFileURL() {
        let url = URL(fileURLWithPath: "/path/to/image.jpg")
        let source = ImageSource.fileURL(url)

        if case .fileURL(let sourceURL) = source {
            XCTAssertEqual(sourceURL, url)
        } else {
            XCTFail("Expected fileURL source")
        }
    }

    func testImageSourceImageData() {
        let data = Data([0xFF, 0xD8, 0xFF]) // JPEG header
        let source = ImageSource.imageData(data, suggestedName: "test.jpg")

        if case .imageData(let sourceData, let name) = source {
            XCTAssertEqual(sourceData, data)
            XCTAssertEqual(name, "test.jpg")
        } else {
            XCTFail("Expected imageData source")
        }
    }

    func testImageSourceClipboard() {
        let source = ImageSource.clipboard(Data())

        if case .clipboard = source {
            // Success
        } else {
            XCTFail("Expected clipboard source")
        }
    }

    func testImageSourceDisplayName() {
        let fileSource = ImageSource.fileURL(URL(fileURLWithPath: "/path/to/photo.jpg"))
        XCTAssertEqual(fileSource.displayName, "photo.jpg")

        let dataSource = ImageSource.imageData(Data(), suggestedName: "screenshot.png")
        XCTAssertEqual(dataSource.displayName, "screenshot.png")

        let clipboardSource = ImageSource.clipboard(Data())
        XCTAssertEqual(clipboardSource.displayName, "Clipboard Image")
    }
}
