import Foundation
import RegexBuilder

protocol TemplateTestRegexMatcher {
  /// The matched section of the output should be captured using the name "match".
  var regex: Regex<AnyRegexOutput> { get }
}

extension TemplateTestRegexMatcher {
  typealias selectionSet = RegexMatcher.SelectionSetTemplate
  typealias operationDefinition = RegexMatcher.OperationDefinitionTemplate
}

enum RegexMatcher {
  nonisolated(unsafe) private static let endOfSection = /\n(?:\n|\h*?}(?:\n|\Z))/
  nonisolated(unsafe) private static let startOfLine = /^\h*?/
  nonisolated(unsafe) static let match = Reference(Substring.self)

  enum SelectionSetTemplate: TemplateTestRegexMatcher {
    case selections
    case fulfilledFragments
    case propertyAccessors(mutable: Bool = false)
    case inlineFragmentAccessors
    case namedFragmentAccessors
    case initializer

    var regex: Regex<AnyRegexOutput> {
      switch self {
      case .selections:
        return .init(Regex {
          Capture(as: match) {
            startOfLine
            /(?:public)? static var __selections: \[ApolloAPI.Selection\] { \[\n.*?\n\h*\] }\n/
          }
        })
        .anchorsMatchLineEndings()
        .dotMatchesNewlines()
      case .fulfilledFragments:
        return .init(Regex {
          Capture(as: match) {
            startOfLine
            /(?:public)? static var __fulfilledFragments: \[any ApolloAPI\.SelectionSet\.Type\] { \[.*?] }/
          }
          endOfSection
        })
        .anchorsMatchLineEndings()
        .dotMatchesNewlines()

      case let .propertyAccessors(mutable):
        let documentationLine = Regex {
          startOfLine
          "/// "
          /[^\n]*?\n/
        }

        let propertyDefinition = Regex {
          ZeroOrMore { documentationLine }
          startOfLine
          /(?:public)? var [`\w]+?: [^\n]+?(?:\?)?\ /
        }
        let getter = /{ __data\["\w+?"\] }\n?/

        let regex = {
          if mutable {
            return Regex {
              Capture(as: match) {
                OneOrMore {
                  propertyDefinition; "{"
                  /\n/; startOfLine
                  "get "; getter
                  startOfLine
                  /set { __data\["\w+?"\] = newValue }\n/
                  startOfLine; "}"
                }
              }
              endOfSection
            }

          } else {
            return Regex {
              Capture(as: match) {
                OneOrMore {
                  propertyDefinition; getter
                }
              }
              endOfSection
            }
          }
        }()

        return .init(regex)
          .repetitionBehavior(.reluctant)
          .anchorsMatchLineEndings()
          .dotMatchesNewlines()

      case .inlineFragmentAccessors:
        return .init(Regex {
          Capture(as: match) {
            OneOrMore {
              startOfLine
              /(?:public)? var \w+: [\w\.]+(?:\?)? { _asInlineFragment\(\) }\n?/
            }
          }
          RegexMatcher.endOfSection
        })
        .repetitionBehavior(.reluctant)
        .anchorsMatchLineEndings()
        .dotMatchesNewlines()

      case .namedFragmentAccessors:
        let startWhitespace = Reference(Substring.self)
        return .init(Regex {
          Capture(as: match) {
            /^/
            Capture(as: startWhitespace) {
              ZeroOrMore(.horizontalWhitespace, .reluctant)
            }
            /public struct Fragments: FragmentContainer {.*?^/
            startWhitespace
            "}"
          }
          RegexMatcher.endOfSection
        })
        .anchorsMatchLineEndings()
        .dotMatchesNewlines()

      case .initializer:
        return .init(Regex {
          Capture(as: match) {
            startOfLine
            /init\(\n[^\)]*?\) {\n/
            startOfLine
            /self.init\(unsafelyWithData: \[\n[^\]]*?\]\)\n/
            startOfLine
            "}"
          }
          endOfSection
        })
        .repetitionBehavior(.reluctant)
        .anchorsMatchLineEndings()
        .dotMatchesNewlines()
      }
    }
  }

  enum OperationDefinitionTemplate: TemplateTestRegexMatcher {
    case responseModel

    var regex: Regex<AnyRegexOutput> {
      switch self {
      case .responseModel:
        let startWhitespace = Reference(Substring.self)
        return .init(Regex {
          Capture(as: match) {
            Anchor.startOfLine
            Capture(as: startWhitespace) {
              OneOrMore(.horizontalWhitespace, .reluctant)
            }
            /(?:public )?struct Data: \w*?\.(?:Root)?SelectionSet {\n.*?/
            Anchor.startOfLine; startWhitespace
            "}"
          }
          endOfSection
        })
        .anchorsMatchLineEndings()
        .dotMatchesNewlines()
      }
    }
  }
}

