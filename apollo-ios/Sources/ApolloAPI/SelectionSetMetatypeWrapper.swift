public struct SelectionSetMetatypeWrapper: Hashable {
  public let metatype: any SelectionSet.Type

  public init(metatype: any SelectionSet.Type) {
    self.metatype = metatype
  }

  public var hashValue: Int {
    return ObjectIdentifier(metatype).hashValue
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(metatype))
  }

  public static func ==(lhs: Self, rhs: Self) -> Bool {
    return lhs.metatype == rhs.metatype
  }
}
