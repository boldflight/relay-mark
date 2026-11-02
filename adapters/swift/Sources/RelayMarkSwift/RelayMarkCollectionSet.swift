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

    /// Groups v1 metadata for the page's records.
    public enum Grouping: String, Sendable {
        case type, status
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
        /// When set, the page carries `groups` for this grouping.
        public var grouping: Grouping?

        public init(list: List, entityID: String? = nil, account: String? = nil, params: [String: Any] = [:], page: Int = 1, pageSize: Int = 24, grouping: Grouping? = nil) {
            self.grouping = grouping
            self.list = list
            self.entityID = entityID
            self.account = account
            self.params = params
            self.page = page
            self.pageSize = pageSize
        }
    }

    /// The page's groups: descriptors in rank order and each entity's group key.
    public struct Groups: Equatable, Sendable {
        public struct Descriptor: Equatable, Sendable {
            public var key: String
            public var label: String
        }
        public var grouping: Grouping
        public var descriptors: [Descriptor]
        public var entityGroupKeys: [String: String]
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
        /// Present when the query named a grouping.
        public var groups: Groups?
    }

    public static func evaluate(records: [[String: Any]], shellEntityTypes: ShellCoverage, query: Query) throws -> Page {
        var input: [String: Any] = [
            "records": records, "shell_entity_types": shellEntityTypes.rawValue, "list": query.list.rawValue,
            "account": query.account ?? NSNull(), "params": query.params, "page": query.page, "page_size": query.pageSize,
        ]
        if let grouping = query.grouping { input["grouping"] = grouping.rawValue }
        if let entityID = query.entityID { input["entity_id"] = entityID }
        let answer = try RelayMarkEngineCall.run("collection_set", try RelayMarkEngineCall.json(input), options: [:])
        guard let result = try JSONSerialization.jsonObject(with: answer) as? [String: Any],
              let status = (result["status"] as? String).flatMap(Page.Status.init(rawValue:)),
              let ids = result["ids"] as? [String], let page = result["page"] as? Int else {
            throw RelayMarkSourceCodec.Failure.invalidInput
        }
        var groups: Groups?
        if let raw = result["groups"] as? [String: Any] {
            guard let grouping = (raw["grouping"] as? String).flatMap(Grouping.init(rawValue:)), let descriptors = raw["descriptors"] as? [[String]],
                  let keys = raw["entity_group_keys"] as? [String: String], descriptors.allSatisfy({ $0.count == 2 }) else {
                throw RelayMarkSourceCodec.Failure.invalidInput
            }
            groups = Groups(grouping: grouping, descriptors: descriptors.map { .init(key: $0[0], label: $0[1]) }, entityGroupKeys: keys)
        }
        return Page(status: status, ids: ids, total: result["total"] as? Int, page: page, pageCount: result["page_count"] as? Int, groups: groups)
    }
}
