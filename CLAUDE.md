# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Setup

This is the apollo-ios-dev repository, a development environment for the Apollo iOS ecosystem using git subtrees. It contains:

- [apollo-ios](https://github.com/apollographql/apollo-ios) - Main Apollo iOS SDK
- [apollo-ios-codegen](https://github.com/apollographql/apollo-ios-codegen) - Code generation library
- [apollo-ios-pagination](https://github.com/apollographql/apollo-ios-pagination) - Pagination support

### Requirements
- Xcode 26.1+
- Swift 6.1 (packages support Swift 5 backward compatibility via `swiftLanguageModes`)
- Tuist 4.119.1 (pinned in `.mise.toml`; install via [Mise](https://mise.jdx.dev/) or `curl -Ls https://install.tuist.io | bash`)
- Node.js v22 (only needed for GraphQL compiler JS tests)

### Initial Setup
1. Install Tuist (see requirements above)
2. Generate workspace: `tuist generate`
3. Use `ApolloDev.xcworkspace` for all development (NOT the .xcodeproj)

## Common Commands

### Building and Testing
- Generate Xcode workspace: `tuist generate`
- Build (codegen package): `cd apollo-ios-codegen && make build`
- Build CLI: `cd apollo-ios-codegen && make build-cli`
- Run tests (codegen): `cd apollo-ios-codegen && make test`
- Test all codegen configurations: `./scripts/run-test-codegen-configurations.sh`
- Test with project validation: `./scripts/run-test-codegen-configurations.sh -t`

### Code Generation
- Run codegen for test projects: `./scripts/run-codegen.sh`
- Build CLI with universal binary: `cd apollo-ios-codegen && make build-cli-universal`
- Archive CLI for release: `cd apollo-ios-codegen && make archive-cli-for-release`

### Package Management
- Archive CLI to apollo-ios package: `make archive-cli-to-apollo-package`
- Clean build artifacts: `cd apollo-ios-codegen && make clean`
- Wipe build directory: `cd apollo-ios-codegen && make wipe`

## Project Architecture

### Repository Structure
- **Sources/**: Test API implementations (AnimalKingdomAPI, StarWarsAPI, GitHubAPI, etc.)
- **Tests/**: Unit tests, performance tests, integration tests
- **Tests/TestCodeGenConfigurations/**: Code generation configuration test projects
- **Tests/TestPlans/**: Xcode test plans for organized test execution
- **apollo-ios/**: Main Apollo iOS library subtree
- **apollo-ios-codegen/**: Code generation library subtree
- **apollo-ios-pagination/**: Pagination library subtree

### Modules by Subtree

**apollo-ios** — `apollo-ios/Sources/`
- `Apollo` — Core networking, caching, and client
- `ApolloAPI` — Type definitions for generated code
- `ApolloSQLite` — SQLite-backed normalized cache
- `ApolloWebSocket` — WebSocket subscriptions (`graphql-transport-ws` protocol)
- `ApolloTestSupport` — Public test utilities

**apollo-ios-codegen** — `apollo-ios-codegen/Sources/`
- `ApolloCodegenLib` — Code generation library
- `CodegenCLI` — CLI command definitions
- `apollo-ios-cli` — CLI executable

**apollo-ios-pagination** — `apollo-ios-pagination/Sources/`
- `ApolloPagination` — Cursor/offset pagination helpers

### Key Components
- **Tuist Project**: Uses `Project.swift` and `Workspace.swift` for workspace generation
- **Test APIs**: 6 GraphQL API implementations in `Sources/` (AnimalKingdomAPI, StarWarsAPI, GitHubAPI, SubscriptionAPI, UploadAPI, Schema)
- **Test Plans**: Organized test execution using Xcode test plans (see Testing Strategy)
- **CLI Integration**: apollo-ios-cli built from codegen package

### Git Subtrees
The three library directories (`apollo-ios/`, `apollo-ios-codegen/`, `apollo-ios-pagination/`) are git subtrees. On PR merge to `main`, GitHub Actions (`.github/workflows/pr-subtree-push.yml`) automatically splits and pushes changes to the respective upstream repositories.

### Development Workflow
1. Make changes in appropriate subtree directory
2. Test using relevant test plans in ApolloDev.xcworkspace
3. Run code generation tests to verify changes
4. On PR merge, subtree changes are automatically pushed to upstream repos

## CI/CD

Primary CI is **GitHub Actions** (`.github/workflows/ci-tests.yml`). CircleCI (`.circleci/config.yml`) only runs security scans (gitleaks, semgrep).

## Testing Strategy

- **Unit Tests**: Core logic testing in each package
- **Integration Tests**: Cross-package functionality testing
- **Code Generation Tests**: Verify codegen output for various configurations
- **Performance Tests**: Benchmark critical code paths
- **CLI Tests**: Command-line interface validation

### Running Tests via Command Line

Tests are run via `xcodebuild` using the `ApolloDev.xcworkspace` with a specific scheme and test plan. The general pattern:

```bash
xcodebuild test \
  -workspace ApolloDev.xcworkspace \
  -scheme <SchemeName> \
  -testPlan <TestPlanName> \
  -destination 'platform=macOS'
```

To run a single test class or method, add `-only-testing`:

```bash
xcodebuild test \
  -workspace ApolloDev.xcworkspace \
  -scheme ApolloTests \
  -testPlan Apollo-UnitTestPlan \
  -destination 'platform=macOS' \
  -only-testing:"ApolloTests/WebSocketTests/testLocalSingleSubscription"
```

### Schemes → Test Plans Mapping

| Scheme | Test Plans | Target |
|--------|-----------|--------|
| `ApolloTests` | `Apollo-UnitTestPlan` (default), `Apollo-CITestPlan` | `ApolloTests` |
| `ApolloCodegenTests` | `Apollo-CodegenTestPlan` (default), `Apollo-Codegen-CITestPlan` | `ApolloCodegenTests` |
| `ApolloPaginationTests` | `Apollo-PaginationTestPlan` | `ApolloPaginationTests` |
| `ApolloPerformanceTests` | `Apollo-PerformanceTestPlan` | `ApolloPerformanceTests` |
| `CodegenCLITests` | `CodegenCLITestPlan` | `CodegenCLITests` |

**Important**: When specifying `-testPlan`, use the filename without the `.xctestplan` extension (e.g., `Apollo-UnitTestPlan`, NOT `Apollo-UnitTestPlan.xctestplan`). The test plan must be one that is associated with the chosen scheme — using a mismatched plan will fail.

### Test Plan Files

All test plan files live in `Tests/TestPlans/`. The scheme-to-plan associations are defined in `Tuist/ProjectDescriptionHelpers/Targets/Target+<SchemeName>.swift`.
