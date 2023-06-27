default: archive-cli-to-apollo-package

archive-cli-to-apollo-package:
	(cd apollo-ios-codegen && make archive-cli-for-release); \
	mkdir -p apollo-ios/CLI; \
	cp -f apollo-ios-codegen/apollo-ios-cli.tar.gz apollo-ios/CLI/apollo-ios-cli.tar.gz