# apollo-ios-codegen

Code generation engine that compiles GraphQL schemas and operations into Swift types.

## Modules

- **ApolloCodegenLib** (`Sources/ApolloCodegenLib/`) — Main code generation library and public API.
- **GraphQLCompiler** (`Sources/GraphQLCompiler/`) — JavaScript-bridged GraphQL frontend using JavaScriptCore.
- **IR** (`Sources/IR/`) — Intermediate representation for GraphQL operations and schema types.
- **CodegenCLI** (`Sources/CodegenCLI/`) — CLI command definitions (generate, fetch-schema, init, generate-operation-manifest).
- **apollo-ios-cli** (`Sources/apollo-ios-cli/`) — CLI executable entry point.
- **TemplateString** (`Sources/TemplateString/`) — String templating engine for code rendering.
- **Utilities** (`Sources/Utilities/`) — Shared utilities (concurrent collections, LinkedList).

## Architecture

### Code Generation Pipeline
1. **Frontend** — `GraphQLJSFrontend` bridges to a TypeScript GraphQL compiler via JavaScriptCore to parse and validate schemas/operations, producing a `CompilationResult`.
2. **IR Building** — `IRBuilder` transforms the compilation result into a Swift intermediate representation (`IR.Operation`, `IR.NamedFragment`, `IR.SelectionSet`, etc.).
3. **File Generation** — Plugin-style `FileGenerator` types render Swift code from IR using `TemplateString`. Generators exist for objects, interfaces, unions, enums, input objects, custom scalars, operations, fragments, and mocks.
4. **Output** — Generated files are written according to `ApolloCodegenConfiguration`.

### Key Types
- `ApolloCodegen.build()` — Main entry point (async)
- `ApolloCodegenConfiguration` — Root configuration (Codable, Sendable)
- `IRBuilder` — Converts compilation results to IR
- `FileGenerator` subclasses — One per generated file type

### CLI Commands
Defined in `Sources/CodegenCLI/Commands/`:
- `Generate` — Run code generation
- `FetchSchema` — Download schema via introspection
- `Initialize` — Create initial configuration file
- `GenerateOperationManifest` — Create persisted queries manifest

## Build Commands (Makefile)
- `make build` — Build release target
- `make build-cli` — Build CLI for current platform
- `make build-cli-universal` — Universal binary (arm64 + x86_64)
- `make test` — Run swift test
- `make clean` / `make wipe` — Clean build artifacts

## Testing
Tests live in the parent `apollo-ios-dev` repo. Use the `ApolloCodegenTests` scheme with `Apollo-CodegenTestPlan`.

## Dependencies
- InflectorKit (pluralization), swift-collections (OrderedCollections), swift-argument-parser (CLI)
