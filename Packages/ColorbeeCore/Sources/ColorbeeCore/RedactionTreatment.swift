/// How Auto-Redact hides what it found (FR-6.4).
public enum RedactionTreatment: CaseIterable, Sendable {
    case blur
    case pixelate
    case solidFill
}
