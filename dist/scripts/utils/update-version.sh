#!/bin/bash

new_version=$1

if [ -z "$new_version" ]; then
  echo "Usage: sh update_version.sh <version>"
  exit 1
fi

jq ".version = \"$new_version\"" version.json > temp.json && mv temp.json version.json

echo "version.json: Updated version to $new_version"