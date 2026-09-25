import Foundation
import YSwift
import RelayMarkProseProjection

/// Exact flat quote grammar shared by the native quote commands.
@MainActor
enum RelayMarkNativeQuote {
    static func paragraphs(root: YXmlNode, projection: RelayMarkCollaborativeProse) throws -> [(node: YXmlNode, text: String)] {
        guard root.length() == 1,
              let quote = root.child(at: 0), quote.kind() == "element", quote.tag() == "blockquote",
              (1...2).contains(Int(quote.length())), projection.isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        var result: [(node: YXmlNode, text: String)] = []
        for index in 0..<Int(quote.length()) {
            guard let paragraph = quote.child(at: UInt32(index)), paragraph.kind() == "element",
                  paragraph.tag() == "paragraph", paragraph.length() <= 1,
                  paragraph.length() == 1 || index == 1 else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            let leaf = paragraph.child(at: 0)
            guard leaf == nil || leaf?.kind() == "text" else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            let text = try leaf?.delta().map(\.text).joined() ?? ""
            guard !text.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}" }) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            result.append((paragraph, text))
        }
        guard result.reduce(0, { $0 + $1.text.utf16.count + 1 }) <= 131_072 else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return result
    }

}
