import XCTest

/// Validates packaging artifacts required by PRD #16 and PRD #39:
/// - Info.plist contains all keys mandated by specs/packaging.md
/// - Info.plist contains the speech-recognition privacy key (PRD #39)
/// - AppIcon.icns exists and is a valid macOS icon file
/// - AppIcon-1024.png exists with correct dimensions
///
/// These checks run against the checked-in Resources/ directory so they
/// catch regressions before a release build.
final class PackagingTests: XCTestCase {

    /// Project root = four levels up from this test file:
    /// Tests/DiaryTranscriberTests/PackagingTests.swift -> repo root
    private let projectRoot: URL = {
        let here = URL(fileURLWithPath: #filePath)
        // Remove: PackagingTests.swift, DiaryTranscriberTests/, Tests/
        return here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    private let resourcesSubpath = "Resources"

    // MARK: - Info.plist

    func testInfoPlist_containsAllMandatoryKeys() throws {
        let plistURL = projectRoot
            .appendingPathComponent(resourcesSubpath)
            .appendingPathComponent("Info.plist")

        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]
        XCTAssertNotNil(plist, "Info.plist must decode as a dictionary")

        let mandatoryKeys: [(String, String, String)] = [
            ("CFBundleIdentifier", "com.compactifai.diarytranscriber", "bundle ID"),
            ("CFBundleName", "DiaryTranscriber", "bundle name"),
            ("CFBundleExecutable", "DiaryTranscriber", "executable name"),
            ("CFBundleShortVersionString", "1.0.0", "marketing version"),
            ("LSMinimumSystemVersion", "14.0", "minimum OS"),
            ("LSApplicationCategoryType", "public.app-category.productivity", "App Store category"),
            ("NSMicrophoneUsageDescription",
             "Diary Transcriber records your voice to create diary entries.",
             "microphone usage description"),
            ("NSSpeechRecognitionUsageDescription",
             "Diary Transcriber uses speech recognition to transcribe your diary entries into text.",
             "speech-recognition usage description (PRD #39)"),
            ("CFBundleIconFile", "AppIcon.icns", "icon file reference"),
            ("CFBundleIconName", "AppIcon", "icon name reference"),
        ]

        for (key, expected, label) in mandatoryKeys {
            guard let value = plist![key] as? String else {
                XCTFail("Missing \(label) key \(key) in Info.plist")
                continue
            }
            XCTAssertEqual(value, expected,
                           "\(label) (\(key)) should be \(expected)")
        }

        // CFBundleVersion must be present and non-empty (numeric string expected).
        let bundleVersion = try XCTUnwrap(plist!["CFBundleVersion"] as? String,
                                          "CFBundleVersion must be present")
        XCTAssertFalse(bundleVersion.isEmpty, "CFBundleVersion must not be empty")
    }

    // MARK: - App icon

    func testAppIcon_icns_existsAndIsValid() throws {
        let icnsURL = projectRoot
            .appendingPathComponent(resourcesSubpath)
            .appendingPathComponent("AppIcon.icns")

        XCTAssertTrue(FileManager.default.fileExists(atPath: icnsURL.path),
                      "AppIcon.icns must exist in Resources/")

        // Valid .icns files start with the magic bytes "icns" (0x69 0x63 6E 73).
        let handle = try FileHandle(forReadingFrom: icnsURL)
        let magic = try handle.read(upToCount: 4)
        try? handle.close()
        XCTAssertEqual(magic, Data([0x69, 0x63, 0x6E, 0x73]),
                       "AppIcon.icns must be a valid macOS icon file (magic: icns)")
    }

    func testAppIcon_1024png_existsWithCorrectDimensions() throws {
        let pngURL = projectRoot
            .appendingPathComponent(resourcesSubpath)
            .appendingPathComponent("AppIcon-1024.png")

        XCTAssertTrue(FileManager.default.fileExists(atPath: pngURL.path),
                      "AppIcon-1024.png must exist in Resources/")

        // PNG signature: 8 bytes starting with 0x89 0x50 0x4E 0x47.
        let handle = try FileHandle(forReadingFrom: pngURL)
        let sig = try handle.read(upToCount: 8)
        try? handle.close()
        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(sig, pngSignature, "AppIcon-1024.png must be a valid PNG file")

        // IHDR chunk (width/height) starts at byte 16:
        //   bytes 0-7  = PNG signature
        //   bytes 8-11 = IHDR length (always 13 → 0x00 0x00 0x00 0x0D)
        //   bytes 12-15 = "IHDR"
        //   bytes 16-19 = width (big-endian UInt32)
        //   bytes 20-23 = height (big-endian UInt32)
        let h2 = try FileHandle(forReadingFrom: pngURL)
        _ = try h2.read(upToCount: 16)          // skip to width
        let widthBytes = try h2.read(upToCount: 4)!
        let heightBytes = try h2.read(upToCount: 4)!
        try? h2.close()

        let width = widthBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let height = heightBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        XCTAssertEqual(Int(width), 1024, "AppIcon-1024.png width must be 1024px")
        XCTAssertEqual(Int(height), 1024, "AppIcon-1024.png height must be 1024px")
    }

    // MARK: - Scripts

    func testPackagingScripts_existAndAreExecutable() throws {
        let scriptsDir = projectRoot.appendingPathComponent("scripts")
        let scripts = ["package.sh", "sign-adhoc.sh", "sign-developer-id.sh", "create-dmg.sh"]

        for name in scripts {
            let path = scriptsDir.appendingPathComponent(name).path
            XCTAssertTrue(FileManager.default.isReadableFile(atPath: path),
                          "\(name) must exist and be readable")
            // Executable bit (user) should be set for every packaging script.
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let permissions = attrs[.posixPermissions] as? NSNumber
            let mode = permissions?.int16Value ?? 0
            XCTAssertTrue((mode & 0o100) != 0,
                          "\(name) must be executable (user-executable bit set)")
        }
    }

    // MARK: - package.sh CWD fix (PRD #37)

    /// Regression test for PRD #37: `scripts/package.sh` computes `PROJECT_ROOT`
    /// but the build previously failed when invoked from another directory
    /// because `xcodebuild` searches the *current* directory for the workspace.
    /// The fix adds an explicit `cd "$PROJECT_ROOT"` after the variable is
    /// computed, wrapped in a fail-fast guard.
    func testPackageScript_changesToProjectRootBeforeXcodebuild() throws {
        let scriptURL = projectRoot
            .appendingPathComponent("scripts/package.sh")

        let source = try String(contentsOf: scriptURL, encoding: .utf8)

        // An explicit `cd "$PROJECT_ROOT"` must appear after PROJECT_ROOT is
        // computed and before `xcodebuild` is invoked.
        XCTAssertTrue(source.contains("cd \"$PROJECT_ROOT\""),
                      "package.sh must cd into $PROJECT_ROOT before invoking xcodebuild")

        // The exit-1 guard must exist so the script fails fast instead of
        // silently continuing from a wrong working directory.
        XCTAssertTrue(source.contains("if ! cd \"$PROJECT_ROOT\"; then"),
                      "package.sh must guard the cd with an if-check")
        XCTAssertTrue(source.contains("echo \"error: cannot cd to project root: $PROJECT_ROOT\" >&2"),
                      "package.sh must print a clear error message to stderr if cd fails")

        // The `if ! cd "$PROJECT_ROOT"` guard must appear BEFORE the actual
        // xcodebuild command (not just any mention of "xcodebuild" in a
        // comment). Search for the guard and the command form specifically.
        let cdGuardRange = source.range(of: "if ! cd \"$PROJECT_ROOT\"")
        let xcodebuildCommandRange = source.range(of: "xcodebuild \\\n  -scheme")
        switch (cdGuardRange, xcodebuildCommandRange) {
        case let (cd?, xb?):
            XCTAssertLessThan(cd.lowerBound, xb.lowerBound,
                              "`if ! cd \"$PROJECT_ROOT\"` must appear before `xcodebuild`")
        case (nil, _):
            XCTFail("package.sh is missing the `if ! cd \"$PROJECT_ROOT\"` guard")
        case (_, nil):
            XCTFail("package.sh is missing the `xcodebuild` command invocation")
        }

        // `set -euo pipefail` (or equivalent fail-fast) must be active so a
        // failed `cd` actually halts the script even if the explicit guard
        // were ever removed.
        XCTAssertTrue(source.contains("set -euo pipefail") || source.contains("set -e"),
                      "package.sh must run with fail-fast shell options set")
    }
}
