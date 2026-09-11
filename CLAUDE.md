# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Distributed Context Convention

Context is distributed across multiple files rather than kept in one large root file. Claude Code auto-discovers CLAUDE.md files by walking up from the working directory, but the `claude/` directory requires explicit reads.

**IMPORTANT — Before working in a subtree directory (`apollo-ios/`, `apollo-ios-codegen/`, or `apollo-ios-pagination/`) or any nested path within one, you MUST read the corresponding context file:**
- Working in `apollo-ios/` or any path under it → read `claude/apollo-ios.md`
- Working in `apollo-ios-codegen/` or any path under it → read `claude/apollo-ios-codegen.md`
- Working in `apollo-ios-pagination/` or any path under it → read `claude/apollo-ios-pagination.md`

When working in a nested subdirectory within a subtree (e.g., `apollo-ios/Sources/Apollo/Caching/`), also check for and read any matching deeper context files in `claude/` (e.g., `claude/apollo-ios/Sources/Apollo/Execution/*.md`).

**When writing or editing code anywhere in this repository, follow the conventions in `claude/code-style.md`.**

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
- **Xcode 26.1+** — the supported floor for local development. Nothing in the repo enforces this floor; CI pins an exact version via `XCODE_VERSION` in the workflows under `.github/workflows/` (currently `26.5`) and runs on `macos-26` runners, so CI is normally ahead of the floor. If you change the floor, update it here — there is no file to derive it from.
- **Swift 6.1** — `swift-tools-version:6.1` in each `Package.swift`; packages support Swift 5 backward compatibility via `swiftLanguageModes: [.v6, .v5]`.
- **Tuist** — the pinned version lives in `.mise.toml`, which is the single source of truth. Do not restate the version in prose; read the file. Install via [Mise](https://mise.jdx.dev/) (`mise install` picks up the pin) or `curl -Ls https://install.tuist.io | bash`.
- **Node.js v22** — only needed for GraphQL compiler JS tests.

### Initial Setup
1. Install Tuist (see requirements above)
2. Configure the repo's git hooks: `make repo-setup` (points `core.hooksPath` at `.githooks/`)
3. Generate workspace: `tuist generate`
4. Use `ApolloDev.xcworkspace` for all development (NOT the .xcodeproj)

## Common Commands

`make` targets live in lowercase `makefile` files: one at the repo root, one in `apollo-ios/`, and one in `apollo-ios-codegen/`. Note the lowercase name — `find . -name Makefile` will not match them.

### Building
- Generate Xcode workspace: `tuist generate`
- Build a package the way CI does: `cd <apollo-ios|apollo-ios-codegen|apollo-ios-pagination> && swift build` (see the `run-swift-builds` job in `.github/workflows/ci-tests.yml`)
- Build codegen package (release config): `cd apollo-ios-codegen && make build` (`swift build -c release`)
- Clean build artifacts: `cd apollo-ios-codegen && make clean` (`swift package clean`)
- Wipe build directory: `cd apollo-ios-codegen && make wipe` (`rm -rf .build`)

### Testing
**There is no `swift test` in this repo.** None of the three `Package.swift` manifests declares a `testTarget`, so `swift test` fails with `error: no tests found; create a target in the 'Tests' directory`.

All Swift tests run through the Xcode schemes and test plans in `ApolloDev.xcworkspace`. See [Schemes → Test Plans Mapping](#schemes--test-plans-mapping) below for the full list, and [Running Tests via Command Line](#running-tests-via-command-line) for the `xcodebuild` invocation. Codegen tests specifically run under the `ApolloCodegenTests` scheme.

Script-driven tests that do work from the command line:
- Test all codegen configurations: `./scripts/run-test-codegen-configurations.sh`
- Same, with project validation: `./scripts/run-test-codegen-configurations.sh -t` (this is what CI runs)
- GraphQL compiler JS tests: `cd apollo-ios-codegen/Sources/GraphQLCompiler/JavaScript && npm install && npm test`

### Code Generation
- Run codegen for test projects: `./scripts/run-codegen.sh`

### CLI and Release
- Build CLI: `cd apollo-ios-codegen && make build-cli`
- Build CLI as a universal binary: `cd apollo-ios-codegen && make build-cli-universal`
- Archive CLI for release: `cd apollo-ios-codegen && make archive-cli-for-release` (universal build + `apollo-ios-cli.tar.gz`)
- Archive CLI into the apollo-ios package: `make archive-cli-to-apollo-package` (from the repo root — archives, then copies the tarball to `apollo-ios/CLI/`). This is the step run by the `Archive CLI` job in `.github/workflows/create-release-pr.yml`; `publish-release.yml` then attaches `apollo-ios/CLI/apollo-ios-cli.tar.gz` to the GitHub release.
- Unpack the vendored CLI tarball: `cd apollo-ios && make unpack-cli`
- Set version numbers across both packages: `./scripts/set-version.sh <version>`

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

**apollo-ios** — `apollo-ios/Sources/`
- `Apollo` — Core networking, caching, and client
- `ApolloAPI` — Type definitions for generated code
- `ApolloSQLite` — SQLite-backed normalized cache
- `ApolloWebSocket` — WebSocket transport (`graphql-transport-ws` protocol) for queries, mutations, and subscriptions
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

### Development Workflow
1. Make changes in appropriate subtree directory
2. Test using relevant test plans in ApolloDev.xcworkspace
3. Run code generation tests to verify changes
4. On PR merge, subtree changes are automatically pushed to upstream repos

## CI/CD

Primary CI is **GitHub Actions** (`.github/workflows/ci-tests.yml`). CircleCI (`.circleci/config.yml`) only runs security scans (gitleaks, semgrep).

Automated PR review and upstream issue triage run through `claude-code-action`; see `.github/claude-automation.md` for the workflows, outcomes, and required secrets. Claude's standing instructions for those runs live in `.github/claude/`.

### GitHub CLI Quirks
- `gh pr edit` may fail with GraphQL deprecation errors for repos using Projects (classic). Use `gh api repos/{owner}/{repo}/pulls/{number} -X PATCH -f title="..." -f body="..."` as a workaround.

### Git Quirks
- **`index.lock` race with Xcode**: Xcode runs `git status` in the background, creating transient `index.lock` files that block git operations. Workaround: chain `rm -f .git/index.lock; git <command>` or use a retry loop: `while ! git <command> 2>/dev/null; do rm -f .git/index.lock; done`

## Tool Preferences

- **Xcode MCP server setup**: the tools below come from the `xcode` MCP server, configured in `.mcp.json` at the repo root as `xcrun mcpbridge`. It ships with Xcode (requires Xcode 26+), so no install is needed, but Claude Code will ask you to approve the project-scoped server the first time you open the repo. If you decline, or `xcrun mcpbridge` is unavailable, none of the tools below exist in your session — fall back to the `xcodebuild` invocations under [Running Tests via Command Line](#running-tests-via-command-line).
- **Use the Xcode MCP tools** (`BuildProject`, `RunSomeTests`, `RunAllTests`, `GetTestList`, etc.) for building and running tests instead of invoking `xcodebuild` directly via Bash.
- **Running tests**: Always use `RunSomeTests` (or `RunAllTests`) from the Xcode MCP. Do NOT run `xcodebuild test` via Bash. Use `GetTestList` to discover available tests and their identifiers first.
- **Known issue — `RunSomeTests` schema bug**: `RunSomeTests` currently returns a `-32602` schema validation error after tests complete, even though the tests ran successfully. To verify test results, call `XcodeListNavigatorIssues` with `severity: "error"` — zero errors means all tests passed.

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
