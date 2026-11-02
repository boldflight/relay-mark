import Foundation

/// relaymark-core's `collection_set` (spec/relaymark/collection-set-v1.json): the
/// smart-list evaluator, which held cards a Composer set shows and in what order.
///
/// It evaluates only the records it is given. A host passes the projection
/// records it holds (`entity.card`, `collection.member` and `workspace.shell`
/// as `{projection, key, payload}`) and never ranks, filters or pages itself.
public enum RelayMarkCollectionSet {
    /// The source whose members and order the set starts from.
    public enum List: String, Sendable {
        case collection, inbox, pinned, recent, shared, trash
    }

    /// Whether the `workspace.shell` entity type catalog is held in full; a
    /// `type_slugs` filter is applied only against a complete one.
    public enum ShellCoverage: String, Sendable {
        case complete, partial
    }

    public struct Query {
        public var list: List
        /// The collection to list; required for `.collection`.
        public var entityID: String?
        /// The viewer, for `content_source` mine/others.
        public var account: String?
        /// The route's Display params: `sort`, `dir`, `completed`, `content_source`,
        /// `type_slugs`, `tag_names` and `text`, as the server's URL params.
        public var params: [String: Any]
        public var page: Int
        public var pageSize: Int

        public init(list: List, entityID: String? = nil, account: String? = nil, params: [String: Any] = [:], page: Int = 1, pageSize: Int = 24) {
            self.list = list
            self.entityID = entityID
            self.account = account
            self.params = params
            self.page = page
            self.pageSize = pageSize
        }
    }

    public struct Page: Equatable, Sendable {
        /// `partial` only when a collection list names a collection that is not held:
        /// then there are no ids and no counts.
        public enum Status: String, Sendable { case complete, partial }
        public var status: Status
        /// The page's entity ids, in order.
        public var ids: [String]
        public var total: Int?
        /// The page shown, clamped into range.
        public var page: Int
        public var pageCount: Int?
    }

    public static func evaluate(records: [[String: Any]], shellEntityTypes: ShellCoverage, query: Query) throws -> Page {
        var input: [String: Any] = [
            "records": records, "shell_entity_types": shellEntityTypes.rawValue, "list": query.list.rawValue,
            "account": query.account ?? NSNull(), "params": query.params, "page": query.page, "page_size": query.pageSize,
        ]
        if let entityID = query.entityID { input["entity_id"] = entityID }
        let answer = try RelayMarkEngineCall.run("collection_set", try RelayMarkEngineCall.json(input), options: [:])
        guard let result = try JSONSerialization.jsonObject(with: answer) as? [String: Any],
              let status = (result["status"] as? String).flatMap(Page.Status.init(rawValue:)),
              let ids = result["ids"] as? [String], let page = result["page"] as? Int else {
            throw RelayMarkSourceCodec.Failure.invalidInput
        }
        return Page(status: status, ids: ids, total: result["total"] as? Int, page: page, pageCount: result["page_count"] as? Int)
    }
}
