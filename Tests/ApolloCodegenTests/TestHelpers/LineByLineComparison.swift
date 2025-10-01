import ApolloCodegenInternalTestHelpers
import ApolloInternalTestHelpers
import Foundation
import Nimble

@testable import ApolloCodegenLib

/// A Nimble matcher that compares two strings line-by-line.
///
/// - Parameters:
///   - expectedValue: The expected string to match against
///   - atLine: [optional] The line in the actual value where matching should begin.
///   This parameter is 1 indexed, representing actual line number, not 0 indexed.
///   If provided, the actual value will be compared to the lines at the given range.
///   Defaults to `nil`.
public func equalLineByLine(
  _ expectedValue: String,
  atLine startLine: Int = 1,
  ignoringExtraLines: Bool = false
) -> Nimble.Matcher<String> {
  return Matcher.define { actual in
    let actualString = try actual.evaluate()

    guard let actualLines = actualString?.lines(startingAt: startLine) else {
      return PrettyPrintedFailureResult(
        actual: actualString,
        message: .fail("Insufficient Lines. Check `atLine` value.")
      )
    }

    return match(actualLines: actualLines, in: actualString, to: expectedValue, ignoringExtraLines: ignoringExtraLines)
  }
}

private func match<S: Collection>(
  actualLines: S,
  in actualString: String?,
  to expectedValue: String,
  ignoringExtraLines: Bool = false
) -> MatcherResult where S.Element == String, S.Index == Int {
  let expectedLines = expectedValue.components(separatedBy: "\n")

  var expectedLinesBuffer: [String] = expectedLines.reversed()

  for index in actualLines.indices {
    let actualLine = actualLines[index]
    guard let expectedLine = expectedLinesBuffer.popLast() else {
      if ignoringExtraLines {
        return MatcherResult(
          status: .matches,
          message: .expectedTo("be equal")
        )
      } else {
        return PrettyPrintedFailureResult(
          actual: actualString,
          message: .fail("Expected actual to end at end of expected string.")
        )
      }
    }

    if actualLine != expectedLine {
      return PrettyPrintedFailureResult(
        actual: actualString,
        message: .fail("Line \(index + 1) did not match. Expected \"\(expectedLine)\", got \"\(actualLine)\".")
      )
    }
  }

  guard expectedLinesBuffer.isEmpty else {
    return MatcherResult(
      status: .fail,
      message: .fail("Expected \(expectedLines.count) lines, actual ended at line \(actualLines.count).")
    )
  }

  return MatcherResult(
    status: .matches,
    message: .expectedTo("be equal")
  )
}

private func PrettyPrintedFailureResult(
  actual: String?,
  message: ExpectationMessage
) -> MatcherResult {
  if let actual = actual {
    print("Actual Document:")
    print(actual)
  }
  return MatcherResult(
    status: .fail,
    message: message
  )
}

// MARK: - Regex Template Matchers

/// A Nimble matcher that compares two strings line-by-line after matching a ``TemplateTestRegexMatcher``
///
/// - Parameters:
///   - expectedValue: The expected string to match against
///   - after: A ``TemplateTestRegexMatcher`` that should be matched in the actual string before starting the comparison.
func equalLineByLine(
  _ expectedValue: String,
  forSection sectionTemplateRegex: any TemplateTestRegexMatcher,
) -> Nimble.Matcher<String> {
  equalLineByLine(
    expectedValue,
    atLine: 1,
    inSection: sectionTemplateRegex,
    ignoringExtraLines: false
  )
}

func equalLineByLine(
  _ expectedValue: String,
  atLine startLine: Int,
  inSection sectionTemplateRegex: any TemplateTestRegexMatcher,
  ignoringExtraLines: Bool = false
) -> Nimble.Matcher<String> {
  return Matcher.define { actual in
    guard let actualString = try actual.evaluate() else {
      return MatcherResult(
        status: .fail,
        message: .expectedActualValueTo("include expected")
      )
    }

    guard
      let regexMatch = try? sectionTemplateRegex.regex
        .firstMatch(in: actualString)?[RegexMatcher.match] as? (any StringProtocol),
      let matchedLines = regexMatch.lines(startingAt: startLine)
    else {
      return PrettyPrintedFailureResult(
        actual: actualString,
        message: .expectedActualValueTo("have match for regex")
      )
    }

    return match(
      actualLines: matchedLines,
      in: actualString,
      to: expectedValue,
      ignoringExtraLines: ignoringExtraLines
    )
  }
}

/// A Nimble matcher that compares two strings line-by-line after matching a ``TemplateTestRegexMatcher``
///
/// - Parameters:
///   - expectedValue: The expected string to match against
///   - after: A ``TemplateTestRegexMatcher`` that should be matched in the actual string before starting the comparison.
func equalLineByLine(
  _ expectedValue: String,
  atLine startLine: Int = 1,
  after afterTemplateRegex: any TemplateTestRegexMatcher,
  ignoringExtraLines: Bool = false
) -> Nimble.Matcher<String> {
  return equalLineByLine(
    expectedValue,
    atLine: startLine,
    after: afterTemplateRegex.regex,
    ignoringExtraLines: ignoringExtraLines
  )
}

private func equalLineByLine(
  _ expectedValue: String,
  atLine startLine: Int = 1,
  after afterRegex: Regex<AnyRegexOutput>,
  ignoringExtraLines: Bool = false
) -> Nimble.Matcher<String> {
  return Matcher.define { actual in
    guard let actualString = try actual.evaluate() else {
      return MatcherResult(
        status: .fail,
        message: .expectedActualValueTo("match expected")
      )
    }

    guard
      let regexMatch = try? afterRegex
        .firstMatch(in: actualString)?[0].value as? any StringProtocol
    else {
      return PrettyPrintedFailureResult(
        actual: actualString,
        message: .expectedActualValueTo("have match for regex")
      )
    }

    let actualStringAfterRegex = actualString[regexMatch.endIndex..<actualString.endIndex]
    guard let actualLines = actualStringAfterRegex.lines(startingAt: startLine) else {
      return PrettyPrintedFailureResult(
        actual: actualString,
        message: .fail("Insufficient Lines. Check `atLine` value.")
      )
    }

    return match(
      actualLines: actualLines,
      in: actualString,
      to: expectedValue,
      ignoringExtraLines: ignoringExtraLines
    )
  }
}

extension StringProtocol {
  fileprivate func lines(startingAt startLine: Int) -> ArraySlice<String>? {
    let allLines = self.components(separatedBy: "\n")
    guard allLines.count >= startLine else { return nil }
    return allLines[(startLine - 1)..<allLines.endIndex]
  }
}

/// Compares line-by-line between the contents of a file and a received string
/// NOTE: Will trim whitespace from the file since Xcode auto-adds a newline
///
/// - Parameters:
///   - received: The string received from the test
///   - expectedFileURL: The file URL to the file with the expected contents of the received string
///   - trimImports: If imports at the top of the file should be trimmed before the comparison.
///                  Defaults to `false`.
public func equalLineByLine(
  toFileAt expectedFileURL: URL,
  trimmingImports trimImports: Bool = false
) -> Nimble.AsyncMatcher<String> {
  return AsyncMatcher.define { actual in
    guard await ApolloFileManager.default.doesFileExist(atPath: expectedFileURL.path) else {
      return MatcherResult(
        status: .fail,
        message: .fail("File not found at \(expectedFileURL)")
      )
    }

    var fileContents = try String(contentsOf: expectedFileURL)
    if trimImports {
      fileContents =
        fileContents
        .components(separatedBy: "\n")
        .filter { !$0.hasPrefix("import ") }
        .joined(separator: "\n")
    }

    let expected = fileContents.trimmingCharacters(in: .whitespacesAndNewlines)

    return try await equalLineByLine(expected).satisfies(actual)
  }
}
