# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Distributed Context Convention

Context is distributed across multiple files rather than kept in one large root file. Claude Code auto-discovers CLAUDE.md files by walking up from the working directory, but the `claude/` directory requires explicit reads.

**IMPORTANT — Before working in a subtree directory (`apollo-ios/`, `apollo-ios-codegen/`, or `apollo-ios-pagination/`) or any nested path within one, you MUST read the corresponding context file:**
- Working in `apollo-ios/` or any path under it → read `claude/apollo-ios.md`
- Working in `apollo-ios-codegen/` or any path under it → read `claude/apollo-ios-codegen.md`
- Working in `apollo-ios-pagination/` or any path under it → read `claude/apollo-ios-pagination.md`

When working in a nested subdirectory within a subtree (e.g., `apollo-ios/Sources/Apollo/Caching/`), also check for and read any matching deeper context files in `claude/` (e.g., `claude/apollo-ios/Sources/Apollo/Execution/*.md`).

These files live in `claude/` instead of inside the subtree directories because anything inside a subtree directory gets pushed to the upstream repo. The `claude/` directory is not auto-discovered, so you must read these files yourself.

**Non-subtree context** (Tests, Sources, scripts, etc.) can use CLAUDE.md files directly in those directories since they are not affected by subtree pushes. For example, `Tests/CLAUDE.md` or `Sources/AnimalKingdomAPI/CLAUDE.md`. These are auto-discovered normally.

When adding new context, place it in the most specific applicable location:
- For subtree content → add to the corresponding file in `claude/`, or create deeper files like `claude/apollo-ios/caching.md`
- For non-subtree content → add a CLAUDE.md in the relevant directory
- For general repo context → add to this root CLAUDE.md

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

## Repository Structure
- **Sources/**: Test API implementations (AnimalKingdomAPI, StarWarsAPI, GitHubAPI, etc.)
- **Tests/**: Unit tests, performance tests, integration tests
- **Tests/TestCodeGenConfigurations/**: Code generation configuration test projects
- **Tests/TestPlans/**: Xcode test plans for organized test execution
- **apollo-ios/**: Main Apollo iOS library subtree (see `claude/apollo-ios.md`)
- **apollo-ios-codegen/**: Code generation library subtree (see `claude/apollo-ios-codegen.md`)
- **apollo-ios-pagination/**: Pagination library subtree (see `claude/apollo-ios-pagination.md`)

## Git Subtrees

The three library directories are git subtrees. On PR merge to `main`, GitHub Actions (`.github/workflows/pr-subtree-push.yml`) automatically splits and pushes changes to the respective upstream repositories. Context files for subtrees are kept in `claude/` (outside subtree directories) so they are never included in subtree pushes.

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
