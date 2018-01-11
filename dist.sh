#!/bin/sh
set -e

if [ $# -eq 0 ]
then
    echo "Please specify the ae folder name."
    exit
fi

rm ae.zip || true
rm -rf "$1"|| true
mkdir -p "$1"/src/ae
cp .travis.yml appveyor.yml dub.json README.md "$1"
cp -r utils "$1"/src/ae/
zip -r "$1".zip "$1"
rm -rf "$1"
