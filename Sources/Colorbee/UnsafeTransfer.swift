/// Hands a pixel buffer to a background task that only reads it while nothing else writes to it.
struct UnsafeTransfer<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
