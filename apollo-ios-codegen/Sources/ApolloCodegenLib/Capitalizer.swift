import Foundation

public enum CapitalizationRule: Codable, Equatable {
  case uppercase(regex: String)
  case lowercase(regex: String)
  case titlecase(regex: String)
  case camelcase(regex: String)
  case pascalcase(regex: String)
}
