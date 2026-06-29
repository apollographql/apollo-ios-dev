import Foundation
import ProjectDescription

enum ApolloTestPlan {
    case cacheBenchmarkTest
    case ciTest
    case codegenTest
    case codegenCITest
    case codegenCLITest
    case paginationTest
    case performanceTest
    case unitTest

    var path: Path {
        switch self {
        case .cacheBenchmarkTest:
            return Path("Tests/TestPlans/Apollo-CacheBenchmarksTestPlan.xctestplan")
        case .ciTest:
            return Path("Tests/TestPlans/Apollo-CITestPlan.xctestplan")
        case .codegenTest:
            return Path("Tests/TestPlans/Apollo-CodegenTestPlan.xctestplan")
        case .codegenCITest:
            return Path("Tests/TestPlans/Apollo-Codegen-CITestPlan.xctestplan")
        case .codegenCLITest:
            return Path("Tests/TestPlans/CodegenCLITestPlan.xctestplan")
        case .paginationTest:
            return Path("Tests/TestPlans/Apollo-PaginationTestPlan.xctestplan")
        case .performanceTest:
            return Path("Tests/TestPlans/Apollo-PerformanceTestPlan.xctestplan")
        case .unitTest:
            return Path("Tests/TestPlans/Apollo-UnitTestPlan.xctestplan")
        }
    }
}
