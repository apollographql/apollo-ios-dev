# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Setup

This is the apollo-ios-dev repository, a development environment for the Apollo iOS ecosystem using git subtrees. It contains:

- [apollo-ios](https://github.com/apollographql/apollo-ios) - Main Apollo iOS SDK
- [apollo-ios-codegen](https://github.com/apollographql/apollo-ios-codegen) - Code generation library
- [apollo-ios-pagination](https://github.com/apollographql/apollo-ios-pagination) - Pagination support

### Initial Setup
1. Install Tuist: `curl -Ls https://install.tuist.io | bash`
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

### Key Components
- **Tuist Project**: Uses Project.swift and Tuist for workspace generation
- **Test APIs**: Multiple GraphQL API implementations for testing different scenarios
- **Test Plans**: Organized test execution using Xcode test plans
- **CLI Integration**: apollo-ios-cli built from codegen package

### Development Workflow
1. Make changes in appropriate subtree directory
2. Test using relevant test plans in ApolloDev.xcworkspace
3. Run code generation tests to verify changes
4. Changes are automatically pushed to respective repositories on PR merge

## Testing Strategy

- **Unit Tests**: Core logic testing in each package
- **Integration Tests**: Cross-package functionality testing
- **Code Generation Tests**: Verify codegen output for various configurations
- **Performance Tests**: Benchmark critical code paths
- **CLI Tests**: Command-line interface validation

Use Xcode test plans for organized test execution. All test targets have corresponding schemes that execute one or more test plans.
- For the migration guide its okay to differentiate between apollo ios 1 and 2.0. In other parts of the documentation, write the docs for the 2.0 version ignoring the 1.0 version