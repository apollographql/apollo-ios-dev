import Foundation
import TemplateString

@testable import ApolloCodegenLib

public struct MockFileTemplate: TemplateRenderer {
  public var target: TemplateTarget
  public var config: ApolloCodegen.ConfigurationContext

  public func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    TemplateString(
      """
      root {
        nested
      }
      """
    )
  }

  public func renderDetachedTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString? {
    TemplateString(
      """
      detached {
        nested
      }
      """
    )
  }

  public static func mock(
    target: TemplateTarget,
    config: ApolloCodegenConfiguration = .mock()
  ) -> Self {
    MockFileTemplate(target: target, config: .init(config: config, rootURL: nil))
  }
}
