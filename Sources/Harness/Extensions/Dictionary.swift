// https://stackoverflow.com/questions/27218669/swift-dictionary-get-key-for-value
public extension Dictionary where Value: Equatable {
    func key(for value: Value) -> Key? {
        return first(where: { $1 == value })?.key
    }
}
