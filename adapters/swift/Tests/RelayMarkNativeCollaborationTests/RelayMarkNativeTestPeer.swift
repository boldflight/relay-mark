import Foundation
import YSwift
@testable import RelayMarkNativeCollaboration

extension RelayMarkNativeDocument {
    /// A peer's raw XML edit, written with plain YSwift and no RelayMark
    /// validation, so tests can deliver shapes no editor command produces.
    func edit(_ operation: Data) throws -> [Data] {
        let op = try JSONSerialization.jsonObject(with: operation) as! [String: Any]
        let path = op["path"] as! [Int], index = UInt32(op["index"] as! Int)
        let scratch = YDocument()
        let current = try encodeUpdate()
        try scratch.transactSync { try $0.transactionApplyUpdate(update: Array(current)) }
        let before = stateVector()
        let root = scratch.getOrCreateXmlFragment(named: "default")
        try scratch.transactSync { tx in
            func append(_ raw: [String: Any], to parent: YXmlNode, at position: UInt32) throws {
                if raw["kind"] as? String == "text" {
                    let leaf = try parent.insertText(at: position, in: tx)
                    for run in raw["delta"] as? [[String: Any]] ?? [] {
                        try leaf.insert(run["insert"] as! String, attributes: run["attributes"] as? [String: Any] ?? [:],
                                        at: leaf.length(in: tx), in: tx)
                    }
                } else {
                    let node = try parent.insertElement(named: raw["name"] as! String, at: position, in: tx)
                    for (key, value) in (raw["attributes"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
                        try node.setAttribute(key, value: value, in: tx)
                    }
                    for child in raw["children"] as? [[String: Any]] ?? [] {
                        try append(child, to: node, at: node.length(in: tx))
                    }
                }
            }
            var target = root
            for step in path { target = target.child(at: UInt32(step), in: tx)! }
            switch op["kind"] as! String {
            case "insertNodes":
                for (offset, node) in (op["nodes"] as! [[String: Any]]).enumerated() {
                    try append(node, to: target, at: index + UInt32(offset))
                }
            case "deleteNodes":
                try target.removeChildren(start: index, length: UInt32(op["length"] as! Int), in: tx)
            case "insertText":
                try target.insert(op["text"] as! String, attributes: [:], at: index, in: tx)
            default:
                throw Failure.unsupportedProseEdit
            }
        }
        let update = try Data(scratch.transactSync { try $0.transactionEncodeStateAsUpdateFromSv(stateVector: Array(before)) })
        try applyUpdate(update)
        return [update]
    }
}
