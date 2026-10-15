/// What an action tool returns after acting. Text (compact OCR) is the cheap default; most screens
/// are fully described by their labels. Screens with almost no text (photos, maps, games, icon-only
/// UI) get the image too, so the model is never left blind.
public enum ReturnMode: String, CaseIterable, Sendable {
    case text, image, both, none

    public static let minTextLines = 3

    public func resolve(ocrLines: Int) -> (text: Bool, image: Bool) {
        switch self {
        case .text: (true, ocrLines < Self.minTextLines)
        case .image: (false, true)
        case .both: (true, true)
        case .none: (false, false)
        }
    }
}
