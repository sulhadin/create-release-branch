#!/bin/bash


ncc build index.js --license licenses.txt


mkdir -p dist/scripts


cp ./scripts/update-version.sh dist/scripts/
cp ./scripts/generate-changelog.sh dist/scripts/
cp ./scripts/create-release-branch.sh dist/scripts/


chmod +x dist/scripts/*.sh

echo "Build completed successfully!"