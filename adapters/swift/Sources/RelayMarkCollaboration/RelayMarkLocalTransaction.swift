import Foundation

/// One local editor transaction. Hosts persist this together with its exact update bytes.
/// Replica replay never creates a contribution; generation provenance belongs to the layer host.
public struct RelayMarkLocalTransaction: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let update: Data
    public let changes: [TextChange]
    /// Local editor operation evidence only. It does not establish authenticated
    /// authorship, ownership of restored text, or contribution replacement rights.
    public let inputIntent: InputIntent?
    /// Exact item-selection JSON captured by the editor for newly inserted text.
    /// Nil means unproven; an empty selection means a proven operation inserted
    /// no text. This local evidence does not establish authenticated authorship.
    /// Freeze these bytes with the update before attempting durable persistence.
    public let insertedTextItems: Data?
    /// A native formatting command, or its actually performed undo/redo, whose
    /// editor verified unchanged text identities. InputIntent distinguishes history.
    /// This is local operation evidence, never an assertion of text authorship.
    public let nativeFormatting: NativeFormatting?
    /// Evidence from the explicit isolated paragraph-end operation. It does not
    /// authorize structural edits or establish ownership of existing prose.
    public let nativeParagraph: NativeParagraph?
    public let nativeParagraphPaste: NativeParagraphPaste?
    /// Exact versioned structural operation/identity lineage JSON. Copied text is
    /// distinct from newly typed text. The host negotiates support and validates
    /// server-side provenance; these bytes alone confer no source ownership.
    /// Persist and retry them with the same transaction/update identity.
    public let proseLineage: Data?
    /// Exact actual maintained command evidence frozen beside the same UUID/update.
    /// Nil means unproven. This carrier does not infer copies or accepted authorship.
    public let nativeContentEdit: NativeContentEdit?

    public struct NativeContentEdit: Codable, Equatable, Sendable {
        public let beforeSnapshot: Data
        public let steps: Data
        /// Exact actual maintained StackItem membership captured before persistence.
        /// Nil retains unproven ordinary command evidence; no membership is inferred.
        public let ownedGroup: OwnedGroup?
        /// Actual same-manager inverse membership; excludes this inverse's UUID.
        /// Normal group and inverse history are mutually exclusive.
        public let ownedHistory: OwnedHistory?
        public init(beforeSnapshot: Data, steps: Data, ownedGroup: OwnedGroup? = nil) {
            self.beforeSnapshot = beforeSnapshot; self.steps = steps; self.ownedGroup = ownedGroup; self.ownedHistory = nil
        }
        public init(beforeSnapshot: Data, steps: Data, ownedHistory: OwnedHistory) {
            self.beforeSnapshot = beforeSnapshot; self.steps = steps
            self.ownedGroup = nil; self.ownedHistory = ownedHistory
        }
        enum CodingKeys: String, CodingKey { case beforeSnapshot, steps, ownedGroup, ownedHistory }
        public init(from decoder: Decoder) throws {
            let container=try decoder.container(keyedBy:CodingKeys.self)
            let group=try container.decodeIfPresent(OwnedGroup.self,forKey:.ownedGroup)
            let history=try container.decodeIfPresent(OwnedHistory.self,forKey:.ownedHistory)
            guard group == nil || history == nil else {
                throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Command group and inverse history are exclusive"))
            }
            self.beforeSnapshot=try container.decode(Data.self,forKey:.beforeSnapshot)
            self.steps=try container.decode(Data.self,forKey:.steps)
            self.ownedGroup=group;self.ownedHistory=history
        }
        public struct OwnedHistory: Codable, Equatable, Sendable {
            public enum Kind: String, Codable, Sendable { case undo, redo }
            public let kind: Kind
            public let reference: UUID
            public let operationIDs: [UUID]
            public init(kind: Kind, reference: UUID, operationIDs: [UUID]) throws {
                let group=try OwnedGroup(reference:reference,operationIDs:operationIDs)
                self.kind=kind;self.reference=group.reference;self.operationIDs=group.operationIDs
            }
            enum CodingKeys: String, CodingKey { case kind,reference,operationIDs }
            public init(from decoder: Decoder) throws {
                let container=try decoder.container(keyedBy:CodingKeys.self)
                try self.init(kind:container.decode(Kind.self,forKey:.kind),reference:container.decode(UUID.self,forKey:.reference),operationIDs:container.decode([UUID].self,forKey:.operationIDs))
            }
        }

        public struct OwnedGroup: Codable, Equatable, Sendable {
            public let reference: UUID
            public let operationIDs: [UUID]
            public init(reference: UUID, operationIDs: [UUID]) throws {
                guard !operationIDs.isEmpty, operationIDs.count <= 4096,
                      operationIDs.first == reference,
                      Set(operationIDs).count == operationIDs.count else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid maintained command membership"))
                }
                self.reference = reference; self.operationIDs = operationIDs
            }
            enum CodingKeys: String, CodingKey { case reference, operationIDs }
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                try self.init(reference: container.decode(UUID.self, forKey: .reference),
                              operationIDs: container.decode([UUID].self, forKey: .operationIDs))
            }
        }
    }

    /// Current native command carrier. The host supplies only actual Change bytes.
    public init(id: UUID = UUID(), update: Data, changes: [TextChange],
                inputIntent: InputIntent? = nil, insertedTextItems: Data? = nil,
                nativeContentEdit: NativeContentEdit) {
        self.id = id; self.update = update; self.changes = changes
        self.inputIntent = inputIntent; self.insertedTextItems = insertedTextItems
        self.nativeContentEdit = nativeContentEdit
        self.nativeFormatting = nil; self.nativeParagraph = nil
        self.nativeParagraphPaste = nil; self.proseLineage = nil; self.attribution = nil
    }

    /// Frozen local candidate only; decoding does not authenticate its assertions.
    public let attribution: AttributionCandidate?

    public struct AttributionCandidate: Codable, Equatable, Sendable {
        public let record: Data
        public let replayBytes: Data
        public let scopeToken: String
        public let documentID: UUID
        public let incarnation: String
        public let replayDigest: String
        public let replayCut: String
        public let inputReplayDigest: String

        public init(record: Data, replay: RelayMarkCollaborationDocument.AttributionReplay,
                    inputReplayDigest: String) throws {
            guard !record.isEmpty, record.count <= 64 * 1024 * 1024,
                  let text = String(data: record, encoding: .utf8), Data(text.utf8) == record,
                  inputReplayDigest.utf8.count == 64,
                  inputReplayDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw RelayMarkCollaborationDocument.Failure.runtime("Invalid attribution candidate")
            }
            self.record = record; self.replayBytes = replay.bytes; self.scopeToken = replay.scopeToken
            self.documentID = replay.binding.documentID; self.incarnation = replay.binding.incarnation
            self.replayDigest = replay.digest; self.replayCut = replay.cut
            self.inputReplayDigest = inputReplayDigest
        }

        /// Recreates host assertions, not semantic validation or authorization.
        public func replay() throws -> RelayMarkCollaborationDocument.AttributionReplay {
            try .init(bytes: replayBytes, scopeToken: scopeToken,
                binding: .init(documentID: documentID, incarnation: incarnation),
                digest: replayDigest, cut: replayCut)
        }
    }

    /// Exact bounded operation evidence; native paste intent and authorization
    /// remain the host's responsibility. Text comes from InputIntent, not here.
    public struct NativeParagraphPaste: Codable, Equatable, Sendable {
        public let paragraphIndex: Int
        public let endUTF16: Int
        public let paragraphCount: Int
        public init(paragraphIndex: Int, endUTF16: Int, paragraphCount: Int) {
            self.paragraphIndex = paragraphIndex; self.endUTF16 = endUTF16; self.paragraphCount = paragraphCount
        }
    }

    public struct NativeParagraph: Codable, Equatable, Sendable {
        public let paragraphIndex: Int
        public let endUTF16: Int
        public init(paragraphIndex: Int, endUTF16: Int) {
            self.paragraphIndex = paragraphIndex; self.endUTF16 = endUTF16
        }
    }

    public struct NativeFormatting: Codable, Equatable, Sendable {
        public enum Mark: String, Codable, Sendable { case bold, italic, strike, code }
        public let startUTF16: Int
        public let lengthUTF16: Int
        public let mark: Mark
        public let enabled: Bool
        public init(startUTF16: Int, lengthUTF16: Int, mark: Mark, enabled: Bool) {
            self.startUTF16 = startUTF16; self.lengthUTF16 = lengthUTF16
            self.mark = mark; self.enabled = enabled
        }
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange]) {
        self.init(id: id, update: update, changes: changes, inputIntent: nil)
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange], inputIntent: InputIntent?) {
        self.init(id: id, update: update, changes: changes, inputIntent: inputIntent, insertedTextItems: nil)
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange], inputIntent: InputIntent?, insertedTextItems: Data?) {
        self.init(id: id, update: update, changes: changes, inputIntent: inputIntent,
                  insertedTextItems: insertedTextItems, nativeFormatting: nil)
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange], inputIntent: InputIntent?,
                insertedTextItems: Data?, nativeFormatting: NativeFormatting?) {
        self.init(id: id, update: update, changes: changes, inputIntent: inputIntent,
                  insertedTextItems: insertedTextItems, nativeFormatting: nativeFormatting, nativeParagraph: nil)
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange], inputIntent: InputIntent?,
                insertedTextItems: Data?, nativeFormatting: NativeFormatting?, nativeParagraph: NativeParagraph?) {
        self.init(id: id, update: update, changes: changes, inputIntent: inputIntent,
                  insertedTextItems: insertedTextItems, nativeFormatting: nativeFormatting,
                  nativeParagraph: nativeParagraph, nativeParagraphPaste: nil)
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange], inputIntent: InputIntent?,
                insertedTextItems: Data?, nativeFormatting: NativeFormatting?, nativeParagraph: NativeParagraph?,
                nativeParagraphPaste: NativeParagraphPaste?) {
        self.init(id: id, update: update, changes: changes, inputIntent: inputIntent,
                  insertedTextItems: insertedTextItems, nativeFormatting: nativeFormatting,
                  nativeParagraph: nativeParagraph, nativeParagraphPaste: nativeParagraphPaste,
                  proseLineage: nil)
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange], inputIntent: InputIntent?,
                insertedTextItems: Data?, nativeFormatting: NativeFormatting?, nativeParagraph: NativeParagraph?,
                nativeParagraphPaste: NativeParagraphPaste?, proseLineage: Data?) {
        self.init(id: id, update: update, changes: changes, inputIntent: inputIntent,
            insertedTextItems: insertedTextItems, nativeFormatting: nativeFormatting,
            nativeParagraph: nativeParagraph, nativeParagraphPaste: nativeParagraphPaste,
            proseLineage: proseLineage, attribution: nil)
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange], inputIntent: InputIntent?,
                insertedTextItems: Data?, nativeFormatting: NativeFormatting?, nativeParagraph: NativeParagraph?,
                nativeParagraphPaste: NativeParagraphPaste?, proseLineage: Data?, attribution: AttributionCandidate?) {
        self.nativeContentEdit = nil
        self.attribution = attribution
        self.id = id
        self.update = update
        self.changes = changes
        self.inputIntent = inputIntent
        self.insertedTextItems = insertedTextItems
        self.nativeFormatting = nativeFormatting
        self.nativeParagraph = nativeParagraph
        self.nativeParagraphPaste = nativeParagraphPaste
        self.proseLineage = proseLineage
    }

    public enum InputIntent: Codable, Equatable, Sendable {
        /// The start is in the pre-edit prose projection's UTF-16 coordinates.
        /// The removed string's UTF-16 length determines the replaced extent.
        case nativeReplacement(startUTF16: Int, removed: String, inserted: String)
        /// A candidate diff without a validated native replacement request.
        case derived
        /// Committed or explicitly reviewed marked input; ownership is unresolved.
        case composition
        /// History restoration is never implicitly new human source material.
        case undo
        case redo
    }

    public struct TextChange: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case insert, replace, delete }
        public let kind: Kind
        public let before: String
        public let after: String
        public let contextBefore: String
        public let contextAfter: String

        /// Describes only changed characters, never attributing the whole merged document to a user.
        public static func between(_ original: String, _ proposed: String) -> [Self] {
            guard original != proposed else { return [] }
            let edit = RelayMarkCollaborativeProse.replacement(from: original, to: proposed)
            let start = String.Index(utf16Offset: edit.start, in: original)
            let end = String.Index(utf16Offset: edit.end, in: original)
            let removed = String(original[start..<end])
            return [Self(kind: removed.isEmpty ? .insert : (edit.text.isEmpty ? .delete : .replace),
                before: removed, after: edit.text,
                contextBefore: String(original[..<start].suffix(80)),
                contextAfter: String(original[end...].prefix(80)))]
        }
    }
}
