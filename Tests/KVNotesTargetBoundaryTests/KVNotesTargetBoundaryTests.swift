import Foundation
import KVNotesCore
import KVNotesKit
import KVNotesTesting
import KVNotesUI
import XCTest

final class KVNotesTargetBoundaryTests: XCTestCase {
    func testGranularProductsAreImportable() {}

    func testCoreImportsFoundationAndNothingElse() throws {
        let coreRoot = try packageRoot()
            .appendingPathComponent("Sources/KVNotesCore", isDirectory: true)
        let sourceFiles = try FileManager.default.subpathsOfDirectory(atPath: coreRoot.path)
            .filter { $0.hasSuffix(".swift") }

        XCTAssertFalse(sourceFiles.isEmpty)
        for path in sourceFiles {
            let source = try String(
                contentsOf: coreRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            let imports = source.split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { $0.hasPrefix("import ") }
            XCTAssertEqual(imports, ["import Foundation"], "\(path) crossed the Core boundary")
        }
    }

    private func packageRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while candidate.path != "/" {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("Package.swift").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
