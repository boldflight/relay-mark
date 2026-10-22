import Foundation
import SwiftUI

/// A pasted or dropped image the host has not received yet.
public struct RelayMarkImageFile: Sendable, Equatable {
    public let filename: String
    public let contentType: String
    public init(filename: String, contentType: String) { self.filename = filename; self.contentType = contentType }
}

/// Where pasted and dropped images go. The editor reads no image itself: it
/// asks for an intake at the caret, then hands the intake the bytes.
@MainActor public protocol RelayMarkImageService {
    /// MIME types the host accepts.
    var acceptedImageTypes: Set<String> { get }
    /// The largest image the host accepts, in bytes.
    var maximumImageBytes: Int { get }
    /// Reserves one image at `range`; nil refuses it.
    func beginImageInput(at range: NSRange, filename: String, contentType: String) -> RelayMarkImageIntake?
    /// Reserves several images at `range` as one insertion; nil refuses them all.
    func beginImageInputs(at range: NSRange, files: [RelayMarkImageFile]) -> [RelayMarkImageIntake]?
}

/// Rich clipboard content. The editor collects the clipboard's HTML items and
/// hands them to the intake; the host converts and inserts them.
@MainActor public protocol RelayMarkPasteService {
    /// Reserves a rich paste of `itemCount` HTML items at `range`; nil refuses it.
    /// `plainText` is the clipboard's plain text, for when the HTML cannot be pasted.
    func beginStructuredPaste(at range: NSRange, itemCount: Int, plainText: String?) -> RelayMarkPasteIntake?
}

/// Links inside the paper, such as `#heading` fragments.
@MainActor public protocol RelayMarkLinkService {
    func activateFragmentLink(_ href: String)
}

/// Paper controls, such as buttons, which act outside the document.
@MainActor public protocol RelayMarkPaperControlService {
    func activatePaperButton(id: String)
}

/// A host command on the paper's selection, such as making a task from it.
/// VoiceOver offers it in the Edit rotor beside Cut, Copy and Paste.
@MainActor public struct RelayMarkSelectionAction {
    /// The localized command name VoiceOver speaks.
    public let name: String
    /// Runs the command on the selection, in paper offsets; false if it could not.
    public let perform: (NSRange) -> Bool
    public init(name: String, perform: @escaping (NSRange) -> Bool) { self.name = name; self.perform = perform }
}

/// What the editor asks of its host. A missing service is a capability the
/// editor does not offer: images and rich pastes are refused, fragment links
/// and buttons do nothing.
@MainActor public struct RelayMarkEditorServices {
    public var images: (any RelayMarkImageService)?
    public var paste: (any RelayMarkPasteService)?
    public var links: (any RelayMarkLinkService)?
    public var paperControls: (any RelayMarkPaperControlService)?
    /// Images for media blocks, loaded by the host.
    public var imageStore: RelayMarkImageStore?
    /// A pasted or dropped input the editor refused, with the reason to show.
    public var inputRefused: ((String) -> Void)?
    /// The color of a collaborator's caret, from the color their client
    /// publishes. The default shows hex colors and grays anything else.
    public var collaboratorColor: (String) -> Color
    /// Commands on the selection that assistive technologies offer as edit actions.
    public var selectionActions: [RelayMarkSelectionAction]
    /// The text view read just before the paper, such as the host's title field:
    /// VoiceOver's line-by-line reading and read-all go from it into the paper.
    public var previousTextElement: (() -> AnyObject?)?
    /// The link to a section of this paper by its destination name, for
    /// "Copy link to this section"; nil offers no link.
    public var sectionLink: ((String) -> URL?)?

    public init(images: (any RelayMarkImageService)? = nil, paste: (any RelayMarkPasteService)? = nil,
                links: (any RelayMarkLinkService)? = nil, paperControls: (any RelayMarkPaperControlService)? = nil,
                imageStore: RelayMarkImageStore? = nil, inputRefused: ((String) -> Void)? = nil,
                collaboratorColor: @escaping (String) -> Color = RelayMarkEditorServices.hexColor,
                selectionActions: [RelayMarkSelectionAction] = [], sectionLink: ((String) -> URL?)? = nil) {
        self.images = images; self.paste = paste; self.links = links; self.paperControls = paperControls
        self.imageStore = imageStore; self.inputRefused = inputRefused; self.collaboratorColor = collaboratorColor
        self.selectionActions = selectionActions; self.sectionLink = sectionLink
    }

    /// `#rrggbb` as that color; anything else gray.
    nonisolated public static func hexColor(_ value: String) -> Color {
        guard value.hasPrefix("#"), let hex = UInt32(value.dropFirst(), radix: 16) else { return .gray }
        return Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                     blue: Double(hex & 255) / 255)
    }
}
