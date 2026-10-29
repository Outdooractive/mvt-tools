#!/bin/sh

protoc --swift_out=. proto/vector_tile.proto
mv proto/vector_tile.pb.swift Sources/MVTTools/Coders/MVT/VectorTile_Tile.swift

# The generated file is only compiled when the MVT trait is enabled.
FILE=Sources/MVTTools/Coders/MVT/VectorTile_Tile.swift
printf '#if EnableMVT\n' | cat - "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
printf '\n#endif\n' >> "$FILE"
