import ProjectDescription

let workspace = Workspace(
    name: "ApolloDev",
    projects: [
        "./"
    ],
    generationOptions: .options(
        enableAutomaticXcodeSchemes: true
    )
)
