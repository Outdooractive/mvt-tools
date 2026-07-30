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

// MARK: - Geometry type enum (matches mlt::metadata::tileset::GeometryType)

enum {
    kMLTGeometryPoint = 0,
    kMLTGeometryLineString = 1,
    kMLTGeometryPolygon = 2,
    kMLTGeometryMultiPoint = 3,
    kMLTGeometryMultiLineString = 4,
    kMLTGeometryMultiPolygon = 5,
    kMLTGeometryUnknown = 99,
};

// MARK: - Decoder lifetime

MLTDecoderHandle mlt_decoder_create(bool supportFastPFOR);
void mlt_decoder_destroy(MLTDecoderHandle decoder);

// MARK: - Decode

MLTTileHandle mlt_tile_decode(
    MLTDecoderHandle decoder,
    const uint8_t* data,
    size_t length);
void mlt_tile_destroy(MLTTileHandle tile);

// MARK: - Tile / Layer introspection

size_t mlt_tile_layer_count(MLTTileHandle tile);
const char* mlt_tile_layer_name(
    MLTTileHandle tile,
    size_t layerIndex);
uint32_t mlt_tile_layer_extent(
    MLTTileHandle tile,
    size_t layerIndex);
size_t mlt_tile_layer_feature_count(
    MLTTileHandle tile,
    size_t layerIndex);

// MARK: - Feature metadata

bool mlt_feature_has_id(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex);
uint64_t mlt_feature_id(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex);
int32_t mlt_feature_geometry_type(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex);
size_t mlt_feature_coordinate_count(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex);

/// Fills the coordinate buffers. Returns the number of coordinates written.
size_t mlt_feature_coordinates(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    float* outX,
    float* outY,
    size_t maxCount);

/// For polygon geometries: number of rings (exterior + holes).
size_t mlt_feature_ring_count(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex);
/// For polygon geometries: coordinate count for a specific ring.
size_t mlt_feature_ring_size(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    size_t ringIndex);
/// Fills coordinate buffers for a specific ring. Returns number of coordinates written.
size_t mlt_feature_ring_coordinates(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    size_t ringIndex,
    float* outX,
    float* outY,
    size_t maxCount);

/// For MultiPolygon: number of polygons in the multi-polygon.
size_t mlt_feature_polygon_count(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex);
/// For MultiPolygon: number of rings in the given polygon (0-indexed).
size_t mlt_feature_polygon_ring_count(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    size_t polygonIndex);

// MARK: - Properties

size_t mlt_layer_property_key_count(
    MLTTileHandle tile,
    size_t layerIndex);
const char* mlt_layer_property_key(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t keyIndex);

int64_t mlt_feature_property_int(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    const char* key,
    bool* found);
double mlt_feature_property_double(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    const char* key,
    bool* found);
const char* mlt_feature_property_string(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    const char* key,
    bool* found);
bool mlt_feature_property_bool(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    const char* key,
    bool* found);

// MARK: - Encoder

typedef void* MLTEncoderHandle;

/// Property value type tag.
enum {
    kMLTPropString = 0,
    kMLTPropInt = 1,       // 32-bit signed integer (use kMLTPropInt64 for larger values)
    kMLTPropDouble = 2,
    kMLTPropBool = 3,
    kMLTPropUInt = 4,      // 32-bit unsigned integer (use kMLTPropUInt64 for larger values)
    kMLTPropFloat = 5,
    kMLTPropInt64 = 6,     // 64-bit signed integer
    kMLTPropUInt64 = 7,    // 64-bit unsigned integer
};

/// A typed property key-value pair.
typedef struct {
    const char* key;
    int32_t type; // one of kMLTProp*
    const char* value; // string representation (always null-terminated)
} MLTProperty;

MLTEncoderHandle mlt_encoder_create(void);
void mlt_encoder_destroy(MLTEncoderHandle encoder);

/// Start a new layer. Call before adding features.
void mlt_encoder_begin_layer(
    MLTEncoderHandle encoder,
    const char* name,
    uint32_t extent);

/// Add a feature to the current layer.
/// `xs`/`ys` are flat float arrays of coordinate data.
/// `geomType` is one of the kMLTGeometry* constants.
/// `partSizes` describes how the flat coordinate array is split into sub-parts
/// (ring/line sizes).  Pass NULL / 0 for simple geometries.
/// `polygonRingCounts` is only used for MultiPolygon: an array (one per polygon)
/// telling how many rings each polygon has.  Pass NULL / 0 otherwise.
void mlt_encoder_add_feature(
    MLTEncoderHandle encoder,
    uint64_t featureId,
    bool hasId,
    int32_t geomType,
    const float* xs,
    const float* ys,
    size_t coordCount,
    const uint32_t* partSizes,
    size_t partCount,
    const uint32_t* polygonRingCounts,
    size_t polygonCount,
    const MLTProperty* props,
    size_t propCount);

/// Finish encoding and return the MLT binary data. Caller must free with `mlt_buffer_free`.
uint8_t* mlt_encoder_finish(
    MLTEncoderHandle encoder,
    size_t* outLength);

/// Free a buffer returned by `mlt_encoder_finish`.
void mlt_buffer_free(uint8_t* buffer);

#ifdef __cplusplus
}
#endif
