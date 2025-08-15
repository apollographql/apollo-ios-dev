import Foundation
import RegexBuilder

protocol TemplateTestRegexMatcher {
  /// The matched section of the output should be captured using the name "match".
  var regex: Regex<AnyRegexOutput> { get }
}

extension TemplateTestRegexMatcher {
  typealias selectionSet = RegexMatcher.SelectionSetTemplate
}

enum RegexMatcher {
  nonisolated(unsafe) private static let endOfSection = /(?:\n\n|\n}\Z)/

  enum SelectionSetTemplate: TemplateTestRegexMatcher {
    case fulfilledFragments
    case propertyAccessors(mutable: Bool = false)
    case inlineFragmentAccessors
    case namedFragmentAccessors

    var regex: Regex<AnyRegexOutput> {
      switch self {
      case .fulfilledFragments:
        return .init(Regex {
          /(?<match>^\h*(?:public)? static var __fulfilledFragments: \[any ApolloAPI\.SelectionSet\.Type\] { \[.*?] })/
          RegexMatcher.endOfSection
        })
        .anchorsMatchLineEndings()
        .dotMatchesNewlines()

      case let .propertyAccessors(mutable):
        if mutable {
          return .init(Regex { /a(g)/ })
        } else {
          return .init(Regex {
            /(?<match>^\h*(?:public)? var \w+: .+(?:\?)? {[\n ].*__data\["\w+"\] })+/
            RegexMatcher.endOfSection
          })
          .repetitionBehavior(.reluctant)
          .anchorsMatchLineEndings()
          .dotMatchesNewlines()
        }

      case .inlineFragmentAccessors:
        return .init(Regex {
          /(?<match>(?:^\h*(?:public)? var \w+: [\w\.]+(?:\?)? { _asInlineFragment\(\) }\n?)+)/
          RegexMatcher.endOfSection
        })
        .repetitionBehavior(.reluctant)
        .anchorsMatchLineEndings()
        .dotMatchesNewlines()

      case .namedFragmentAccessors:
        return .init(Regex {
          /(?<match>^(\h*)public struct Fragments: FragmentContainer {.*?^\2})/
          RegexMatcher.endOfSection
        })
        .anchorsMatchLineEndings()
        .dotMatchesNewlines()
      }
    }
  }
}

