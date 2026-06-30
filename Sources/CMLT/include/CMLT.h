#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Opaque handles

typedef void* MLTDecoderHandle;
typedef void* MLTTileHandle;

// MARK: - Geometry type enum

enum {
    kMLTGeometryUnknown = 0,
    kMLTGeometryPoint = 1,
    kMLTGeometryMultiPoint = 2,
    kMLTGeometryLineString = 3,
    kMLTGeometryMultiLineString = 4,
    kMLTGeometryPolygon = 5,
    kMLTGeometryMultiPolygon = 6,
};

// MARK: - Decoder lifetime

MLTDecoderHandle mlt_decoder_create(bool supportFastPFOR);
void mlt_decoder_destroy(MLTDecoderHandle decoder);

// MARK: - Decode

MLTTileHandle mlt_tile_decode(MLTDecoderHandle decoder, const uint8_t* data, size_t length);
void mlt_tile_destroy(MLTTileHandle tile);

// MARK: - Tile / Layer introspection

size_t mlt_tile_layer_count(MLTTileHandle tile);
const char* mlt_tile_layer_name(MLTTileHandle tile, size_t layerIndex);
uint32_t mlt_tile_layer_extent(MLTTileHandle tile, size_t layerIndex);
size_t mlt_tile_layer_feature_count(MLTTileHandle tile, size_t layerIndex);

// MARK: - Feature metadata

bool mlt_feature_has_id(MLTTileHandle tile, size_t layerIndex, size_t featureIndex);
uint64_t mlt_feature_id(MLTTileHandle tile, size_t layerIndex, size_t featureIndex);
int32_t mlt_feature_geometry_type(MLTTileHandle tile, size_t layerIndex, size_t featureIndex);
size_t mlt_feature_coordinate_count(MLTTileHandle tile, size_t layerIndex, size_t featureIndex);

/// Fills the coordinate buffers. Returns the number of coordinates written.
size_t mlt_feature_coordinates(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    float* outX,
    float* outY,
    size_t maxCount);

/// For polygon geometries: number of rings (exterior + holes).
size_t mlt_feature_ring_count(MLTTileHandle tile, size_t layerIndex, size_t featureIndex);
/// For polygon geometries: coordinate count for a specific ring.
size_t mlt_feature_ring_size(MLTTileHandle tile, size_t layerIndex, size_t featureIndex, size_t ringIndex);
/// Fills coordinate buffers for a specific ring. Returns number of coordinates written.
size_t mlt_feature_ring_coordinates(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    size_t ringIndex,
    float* outX,
    float* outY,
    size_t maxCount);

// MARK: - Properties

size_t mlt_layer_property_key_count(MLTTileHandle tile, size_t layerIndex);
const char* mlt_layer_property_key(MLTTileHandle tile, size_t layerIndex, size_t keyIndex);

int64_t mlt_feature_property_int(MLTTileHandle tile, size_t layerIndex, size_t featureIndex, const char* key, bool* found);
double mlt_feature_property_double(MLTTileHandle tile, size_t layerIndex, size_t featureIndex, const char* key, bool* found);
const char* mlt_feature_property_string(MLTTileHandle tile, size_t layerIndex, size_t featureIndex, const char* key, bool* found);
bool mlt_feature_property_bool(MLTTileHandle tile, size_t layerIndex, size_t featureIndex, const char* key, bool* found);

#ifdef __cplusplus
}
#endif
