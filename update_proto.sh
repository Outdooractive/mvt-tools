#!/bin/sh

protoc --swift_out=. proto/vector_tile.proto
mv proto/vector_tile.pb.swift Sources/MVTTools/VectorTile_Tile.swift
