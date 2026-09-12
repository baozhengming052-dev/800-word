import Foundation

// Check the actual archived product through Apple's Bundle API, not only plistlib.
// Run by CI after archive and before packaging. It is not part of the iOS target.
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift tests/BundleArchiveCheck.swift <Words800App.app>")
}
let appURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard !FileManager.default.fileExists(atPath: appURL.appendingPathComponent("Resources").path) else {
    fatalError("Invalid iOS bundle: custom Resources directory shadows flat bundle metadata")
}
guard let bundle = Bundle(url: appURL), bundle.bundleIdentifier == "com.peanut13.words800" else {
    fatalError("Archived application Bundle API cannot read the expected bundle identifier")
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
print("PASS: native Bundle identifier, executable, 865 words and source PDF")
