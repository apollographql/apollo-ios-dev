# Readme (WIP)

## Tuist

This project uses [Tuist](https://tuist.io/) to handle generation of the Xcode project/workspace for development. In order to use Tuist run the following command in terminal to ensure you have it installed:

```
curl -Ls https://install.tuist.io | bash
```

In order to generate the project/workspace you will need to run the [tuist generate](https://docs.tuist.io/commands/generate) command from the project root.

There is also a githook setup to auto-run `tuist generate` whenever a new branch is checked out, in order for git to find and use the hook run the following make command to ensure the git config is pointing to the correct location:

```
make repo-setup
```

A [Get started](https://docs.tuist.io/tutorial/get-started) guide for Tuist along with [other documentation](https://tuist.github.io/tuist/main/documentation/projectdescription/project) is also available for reference.