#!/bin/bash

#touch $GITHUB_ENV
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.3/install.sh | bash
echo 'export NVM_DIR="$HOME/.nvm"<<EOF' >> $GITHUB_ENV
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"<<EOF' >> $GITHUB_ENV
echo nvm install v12.22.10 >> $GITHUB_ENV
echo nvm use v18.15.0 >> $GITHUB_ENV
