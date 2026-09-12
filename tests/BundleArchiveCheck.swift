import Foundation

// Check the actual archived product through Apple's Bundle API, not only plistlib.
// Run by CI after archive and before packaging. It is not part of the iOS target.
guard CommandLine.arguments.count == 4 else {
    fatalError("Usage: swift tests/BundleArchiveCheck.swift <Words800App.app> <version> <build>")
}
let appURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard !FileManager.default.fileExists(atPath: appURL.appendingPathComponent("Resources").path) else {
    fatalError("Invalid iOS bundle: custom Resources directory shadows flat bundle metadata")
}
guard let bundle = Bundle(url: appURL), bundle.bundleIdentifier == "com.peanut13.words800" else {
    fatalError("Archived application Bundle API cannot read the expected bundle identifier")
}
guard bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == CommandLine.arguments[2],
      bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == CommandLine.arguments[3],
      bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "政名政利公考800词" else {
    fatalError("Archived app version/build/name does not match this release")
}
guard let libraryURL = bundle.url(forResource: "library", withExtension: "json"),
      let sourceURL = bundle.url(forResource: "source", withExtension: "pdf"),
      let executableURL = bundle.executableURL,
      FileManager.default.isReadableFile(atPath: executableURL.path) else {
    fatalError("Archived bundle has missing library, PDF or executable")
}
let data = try Data(contentsOf: libraryURL)
guard let library = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let words = library["words"] as? [[String: Any]], words.count == 865,
      try Data(contentsOf: sourceURL).starts(with: Data("%PDF-".utf8)) else {
    fatalError("Archived learning resources are invalid")
}
print("PASS: native Bundle identifier, release version/name, executable, 865 words and source PDF")
