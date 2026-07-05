#!/bin/sh

protoc --swift_out=. proto/vector_tile.proto
mv proto/vector_tile.pb.swift Sources/MVTTools/Coders/VectorTile_Tile.swift
