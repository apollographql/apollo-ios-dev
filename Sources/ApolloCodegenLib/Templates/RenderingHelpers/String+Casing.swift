extension String {
  var firstUppercased: String {
    guard let indexToChangeCase = firstIndex(where: \.isCased) else {
      return self
    }
    return prefix(through: indexToChangeCase).uppercased() +
    suffix(from: index(after: indexToChangeCase))
  }

  var firstLowercased: String {
    guard let indexToChangeCase = firstIndex(where: \.isCased) else {
      return self
    }
    return prefix(through: indexToChangeCase).lowercased() +
    suffix(from: index(after: indexToChangeCase))
  }

  var isAllUppercased: Bool {
    return self == self.uppercased()
  }

}
