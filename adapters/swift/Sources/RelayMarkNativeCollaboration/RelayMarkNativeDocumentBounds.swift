extension RelayMarkNativeDocument {
    /// The specification's sanity bound on identified blocks in a document
    /// (spec/relaymark/README.md, Canonical AST). Commands that add blocks
    /// refuse only past it; a host's state budget is reached first.
    public static let maximumBlocks = 131_072
}
