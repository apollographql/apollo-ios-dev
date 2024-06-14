public struct SelectionSetMetatype: Hashable {
  public let wrapped: any SelectionSet.Type

  public init(_ type: any SelectionSet.Type) {
    self.wrapped = type
  }

  public var hashValue: Int {
    return ObjectIdentifier(wrapped).hashValue
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(wrapped))
  }

  public static func ==(lhs: Self, rhs: Self) -> Bool {
    return lhs.wrapped == rhs.wrapped
  }
}
