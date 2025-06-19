#!/bin/bash

new_version=$1
version_file=$2

if [ -z "$new_version" ]; then
  echo "Usage: sh update_version.sh <version> <version_file>"
  exit 1
fi

if [ -z "$version_file" ]; then
  echo "Usage: sh update_version.sh <version> <version_file>"
  exit 1
fi


#jq ".version = \"$new_version\"" version.json > temp.json && mv temp.json version.json
jq ".version = \"$new_version\"" "$version_file" > "${version_file}.tmp" && mv "${version_file}.tmp" "$version_file"


echo "version.json: Updated version to $new_version"