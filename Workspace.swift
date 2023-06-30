import ProjectDescription

let workspace = Workspace(
    name: "ApolloDev",
    projects: [
        "./"
    ],
    additionalFiles: [
        .folderReference(path: "apollo-ios"),
        .folderReference(path: "apollo-ios-codegen")
    ],
    generationOptions: .options(
        enableAutomaticXcodeSchemes: true
    )
)
