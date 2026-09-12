import Foundation

nonisolated enum HelpManualEditing {
    static func needsSavePrompt(current: String, saved: String) -> Bool { current != saved }
    static func permitsSave(isManual: Bool, explicit: Bool) -> Bool { !isManual || explicit }
}
