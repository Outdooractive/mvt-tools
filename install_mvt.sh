#!/bin/sh

swift build -c release --arch arm64 --arch x86_64 --product mvt >/dev/null
if [[ $? -ne 0 ]]
then
    echo "Failed to build 'mvt'"
    exit 1
fi

cp .build/apple/Products/Release/mvt /usr/local/bin/
if [[ $? -ne 0 ]]
then
    echo "Failed to copy 'mvt' to /usr/local/bin"
    exit 1
fi

echo "'mvt' installed in /usr/local/bin"
exit 0
