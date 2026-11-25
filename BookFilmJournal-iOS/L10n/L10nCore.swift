import Foundation

enum L10nCore {
    private static let table: [String: String] = {
        guard let url = Bundle.main.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: "zh-Hans.lproj"
        ), let dictionary = NSDictionary(contentsOf: url) as? [String: String] else {
            return [:]
        }
        return dictionary
    }()

    static func string(_ key: String, _ args: CVarArg...) -> String {
        let format = table[key] ?? Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
        guard !args.isEmpty else { return format }
        return String(format: format, arguments: args)
    }
}
