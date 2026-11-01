/// Hands a value across threads where the compiler can't check it: a buffer a background task only reads while nothing
/// else writes to it, or one made there and handed back to be owned alone. Each use says why it's safe.
struct UnsafeTransfer<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
