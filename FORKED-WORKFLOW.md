# Apollo iOS Forked Workflow Guide

When working with Apollo iOS and forking the repositories, there are some scenarios that may arise in which you have questions on the best way to proceed. This guide will collect these questions and aim to provide clarity for these different scenarios.

This guide assumes you have read the [CONTRIBUTING](https://github.com/apollographql/apollo-ios-dev/blob/main/CONTRIBUTING.md) guide to get an overview of how our repositories are structured and worked on. Please submit an issue to the [apollo-ios](https://github.com/apollographql/apollo-ios/issues) repository.

## Questions

### Testing changes for a specific Apollo iOS package

As outlined in the [CONTRIBUTING](https://github.com/apollographql/apollo-ios-dev/blob/main/CONTRIBUTING.md) guide, all development work for Apollo iOS happens through the [apollo-ios-dev](https://github.com/apollographql/apollo-ios-dev) repo. If you are working on changes for one (or more) Apollo iOS packages you may want to push these changes to a branch that you can point your `Package.swift` file to in order to test changes. For the purposes of this guide we will assume we are working on changes for [apollo-ios](https://github.com/apollographql/apollo-ios).

To start with you should create a fork for both `apollo-ios-dev` and `apollo-ios` to work from.

Once you have your forks, create a branch off of `main` in your `apollo-ios-dev` fork to make your changes in. From here you can open the `ApolloDev.xcworkspace` and perform the changes you are planning to make.

After you have made your changes, you can make a commit and then all that is left to do is get your changes pushed to a branch in your `apollo-ios` fork that you can point your `Package.swift` to.

Our development workflow uses git subtree's to bring all of our different packages into the `apollo-ios-dev` repo for development. To assist in running the proper commands to push your code to your `apollo-ios` fork we have provided a basic script that allows you to pass in the pakcage you are pushing to (in this case `apollo-ios`), remote (name or URL), and branch name you would like to push to in your `apollo-ios` fork.

Run the following command in terminal

```
sh scripts/push-forked-branch.sh -p <package name> -r <remote name/url> -b <branch name>
```

This will handle pushing the given subtree package changes to your remote/branch.

At this point you should now be able to point your `Package.swift` to the branch you just pushed on your `apollo-ios` fork to test your changes.

You can continue to commit and push changes as much as you want. After completing your changes if you are planning to contribute them back to the main Apollo iOS repositories you can open a pull request to the main `apollo-ios-dev` repo for review.