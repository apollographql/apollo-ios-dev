extension String {
  func convertedToSingleLine() -> String {
    return components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .joined(separator: " ")
  }
}
