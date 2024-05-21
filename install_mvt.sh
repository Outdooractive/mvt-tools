#!/bin/sh

echo "Building the 'mvt' command line tool..."

swift build --quiet -c release --arch arm64 --arch x86_64 --product mvt 2>&1 >/dev/null
if [[ $? -ne 0 ]]
then
    echo "Failed to build 'mvt'"
    exit 1
fi

if [[ ! -d "/usr/local/bin" ]]
then
    echo "/usr/local/bin doesn't exist, trying to create it (with sudo)"
    sudo mkdir -p /usr/local/bin || exit 1
fi

cp .build/apple/Products/Release/mvt /usr/local/bin/
if [[ $? -ne 0 ]]
then
    echo "Failed to copy 'mvt' to /usr/local/bin"
    exit 1
fi

echo "'mvt' installed in /usr/local/bin"
exit 0
