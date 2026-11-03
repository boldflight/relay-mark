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
        case type, status, date
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
        /// The settings timezone (IANA) a `.date` grouping reads local dates in; blank, "UTC" or an
        /// unknown zone resolve to "Etc/UTC".
        public var timezone: String?

        public init(list: List, entityID: String? = nil, account: String? = nil, params: [String: Any] = [:], page: Int = 1, pageSize: Int = 24, grouping: Grouping? = nil, timezone: String? = nil) {
            self.timezone = timezone
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
            /// A type group's own name; nil for a status group, whose words the client resolves at render.
            public var label: String?
        }
        public var grouping: Grouping
        public var descriptors: [Descriptor]
        public var entityGroupKeys: [String: String]
        /// A `.date` grouping: the resolved timezone the dates are local to.
        public var dateContext: String?
        /// A `.date` grouping: each descriptor key's rank, `[0, gregorianDays]` or `[1]` for undated.
        public var sortKeys: [String: [Int]]?
    }

    public struct Page: Equatable, Sendable {
        /// `partial` only when a collection list names a collection that is not held or is server-projected:
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

    /// The same evaluator for records held as dictionaries: they are encoded once and handed to
    /// `evaluate(recordsJSON:)`.
    public static func evaluate(records: [[String: Any]], shellEntityTypes: ShellCoverage, serverProjected: Set<String> = [], query: Query) throws -> Page {
        guard JSONSerialization.isValidJSONObject(records) else { throw RelayMarkSourceCodec.Failure.invalidInput }
        return try evaluate(recordsJSON: JSONSerialization.data(withJSONObject: records), shellEntityTypes: shellEntityTypes, serverProjected: serverProjected, query: query)
    }

    /// The evaluator. `recordsJSON` is a UTF-8 JSON array of `{projection, key, payload}` records,
    /// for example cached per card as bytes and joined: its bytes go into the job's input as they
    /// are, never decoded and encoded again here. The engine validates them; malformed input throws.
    ///
    /// `serverProjected` is the population manifest's `collection.member` `server_projected` list:
    /// a collection named there is answered `partial` (its pages come from the server), as is one whose
    /// card is not held. Every other collection is evaluated from the records.
    public static func evaluate(recordsJSON: Data, shellEntityTypes: ShellCoverage, serverProjected: Set<String> = [], query: Query) throws -> Page {
        var input: [String: Any] = [
            "shell_entity_types": shellEntityTypes.rawValue, "list": query.list.rawValue,
            "account": query.account ?? NSNull(), "params": query.params, "page": query.page, "page_size": query.pageSize,
        ]
        if let grouping = query.grouping { input["grouping"] = grouping.rawValue }
        if let entityID = query.entityID { input["entity_id"] = entityID }
        if let timezone = query.timezone { input["timezone"] = timezone }
        if !serverProjected.isEmpty { input["server_projected"] = serverProjected.sorted() }
        // Splice the records into the envelope: `{` + `"records":<bytes>,` + the rest of the object.
        var envelope = try RelayMarkEngineCall.json(input)
        guard envelope.first == UInt8(ascii: "{"), envelope.count > 2 else { throw RelayMarkSourceCodec.Failure.invalidInput }
        envelope.replaceSubrange(1..<1, with: Data(#""records":"#.utf8) + recordsJSON + Data(",".utf8))
        let answer = try RelayMarkEngineCall.run("collection_set", envelope, options: [:])
        guard let result = try JSONSerialization.jsonObject(with: answer) as? [String: Any],
              let status = (result["status"] as? String).flatMap(Page.Status.init(rawValue:)),
              let ids = result["ids"] as? [String], let page = result["page"] as? Int else {
            throw RelayMarkSourceCodec.Failure.invalidInput
        }
        var groups: Groups?
        if let raw = result["groups"] as? [String: Any] {
            guard let grouping = (raw["grouping"] as? String).flatMap(Grouping.init(rawValue:)), let descriptors = raw["descriptors"] as? [[String]],
                  let keys = raw["entity_group_keys"] as? [String: String], descriptors.allSatisfy({ (1...2).contains($0.count) }) else {
                throw RelayMarkSourceCodec.Failure.invalidInput
            }
            groups = Groups(grouping: grouping, descriptors: descriptors.map { .init(key: $0[0], label: $0.count > 1 ? $0[1] : nil) }, entityGroupKeys: keys,
                            dateContext: (raw["date_context"] as? [String: Any])?["timezone"] as? String, sortKeys: raw["sort_keys"] as? [String: [Int]])
        }
        return Page(status: status, ids: ids, total: result["total"] as? Int, page: page, pageCount: result["page_count"] as? Int, groups: groups)
    }
}
