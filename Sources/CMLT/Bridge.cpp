#include "CMLT.h"

#include <mlt/decoder.hpp>
#include <mlt/encoder.hpp>
#include <mlt/feature.hpp>
#include <mlt/geometry.hpp>
#include <mlt/layer.hpp>
#include <mlt/properties.hpp>
#include <mlt/tile.hpp>

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

// C++ exceptions must be caught before reaching Swift.
#define TRY_BRIDGE try
#define CATCH_BRIDGE_RET(VAL) catch (...) { return VAL; }
#define CATCH_BRIDGE_VOID catch (...) { }

// MARK: - Decoder

MLTDecoderHandle mlt_decoder_create(bool supportFastPFOR) {
    auto* decoder = new mlt::Decoder(supportFastPFOR);
    return static_cast<MLTDecoderHandle>(decoder);
}

void mlt_decoder_destroy(MLTDecoderHandle decoder) {
    delete static_cast<mlt::Decoder*>(decoder);
}

// MARK: - Tile

MLTTileHandle mlt_tile_decode(
    MLTDecoderHandle decoder,
    const uint8_t* data,
    size_t length)
{ try {
    auto* dec = static_cast<mlt::Decoder*>(decoder);
    auto tile = new mlt::MapLibreTile(
        dec->decode(mlt::DataView(
            reinterpret_cast<const char*>(data), length)));
    return static_cast<MLTTileHandle>(tile);
} CATCH_BRIDGE_RET(nullptr)}

void mlt_tile_destroy(MLTTileHandle tile) { try {
    delete static_cast<mlt::MapLibreTile*>(tile);
} CATCH_BRIDGE_VOID}

size_t mlt_tile_layer_count(MLTTileHandle tile) { try {
    return static_cast<mlt::MapLibreTile*>(tile)->getLayers().size();
} CATCH_BRIDGE_RET(0)}

const char* mlt_tile_layer_name(
    MLTTileHandle tile,
    size_t layerIndex)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return nullptr; }
    return layers[layerIndex].getName().c_str();
} CATCH_BRIDGE_RET(nullptr)}

uint32_t mlt_tile_layer_extent(
    MLTTileHandle tile,
    size_t layerIndex)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return 0; }
    return layers[layerIndex].getExtent();
} CATCH_BRIDGE_RET(0)}

size_t mlt_tile_layer_feature_count(
    MLTTileHandle tile,
    size_t layerIndex)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return 0; }
    return layers[layerIndex].getFeatures().size();
} CATCH_BRIDGE_RET(0)}

// MARK: - Feature

bool mlt_feature_has_id(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return false; }
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) { return false; }
    return features[featureIndex].getID().has_value();
} CATCH_BRIDGE_RET(false)}

uint64_t mlt_feature_id(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return 0; }
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) { return 0; }
    auto id = features[featureIndex].getID();
    return id.has_value() ? id.value() : 0;
} CATCH_BRIDGE_RET(0)}

int32_t mlt_feature_geometry_type(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex)
{ try {
    using GT = mlt::metadata::tileset::GeometryType;

    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return 0; }
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) { return 0; }

    auto& geom = features[featureIndex].getGeometry();
    switch (geom.type) {
        case GT::POINT: return kMLTGeometryPoint;
        case GT::MULTIPOINT: return kMLTGeometryMultiPoint;
        case GT::LINESTRING: return kMLTGeometryLineString;
        case GT::MULTILINESTRING: return kMLTGeometryMultiLineString;
        case GT::POLYGON: return kMLTGeometryPolygon;
        case GT::MULTIPOLYGON: return kMLTGeometryMultiPolygon;
        default: return kMLTGeometryUnknown;
    }
} CATCH_BRIDGE_RET(0)}

// MARK: - Coordinate access

static size_t collectCoordinates(
    const mlt::geometry::Geometry& geom,
    float* outX,
    float* outY,
    size_t maxCount)
{
    using GT = mlt::metadata::tileset::GeometryType;
    size_t written = 0;

    auto write = [&](const mlt::CoordVec& coords) {
        for (const auto& c : coords) {
            if (written >= maxCount) { return; }
            if (outX) { outX[written] = c.x; }
            if (outY) { outY[written] = c.y; }
            written++;
        }
    };

    switch (geom.type) {
        case GT::POINT: {
            const auto& pt = static_cast<const mlt::geometry::Point&>(geom);
            if (written < maxCount) {
                if (outX) { outX[written] = pt.getCoordinate().x; }
                if (outY) { outY[written] = pt.getCoordinate().y; }
                written++;
            }
            break;
        }
        case GT::MULTIPOINT:
        case GT::LINESTRING: {
            const auto& mp = static_cast<const mlt::geometry::MultiPoint&>(geom);
            write(mp.getCoordinates());
            break;
        }
        case GT::MULTILINESTRING: {
            const auto& mls = static_cast<const mlt::geometry::MultiLineString&>(geom);
            for (const auto& ls : mls.getLineStrings()) {
                write(ls);
            }
            break;
        }
        case GT::POLYGON: {
            const auto& poly = static_cast<const mlt::geometry::Polygon&>(geom);
            for (const auto& ring : poly.getRings()) {
                write(ring);
            }
            break;
        }
        case GT::MULTIPOLYGON: {
            const auto& mpoly = static_cast<const mlt::geometry::MultiPolygon&>(geom);
            for (const auto& polygon : mpoly.getPolygons()) {
                for (const auto& ring : polygon) {
                    write(ring);
                }
            }
            break;
        }
        default:
            break;
    }

    return written;
}

size_t mlt_feature_coordinate_count(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return 0; }
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) { return 0; }
    return collectCoordinates(
        features[featureIndex].getGeometry(), nullptr, nullptr, SIZE_MAX);
} CATCH_BRIDGE_RET(0)}

size_t mlt_feature_coordinates(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    float* outX,
    float* outY,
    size_t maxCount)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return 0; }
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) { return 0; }
    return collectCoordinates(
        features[featureIndex].getGeometry(), outX, outY, maxCount);
} CATCH_BRIDGE_RET(0)}

// MARK: - Ring access (for polygon geometries)

size_t mlt_feature_ring_count(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex)
{ try {
    using GT = mlt::metadata::tileset::GeometryType;

    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return 0; }
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) { return 0; }

    auto& geom = features[featureIndex].getGeometry();
    switch (geom.type) {
        case GT::POLYGON:
            return static_cast<const mlt::geometry::Polygon&>(geom).getRings().size();
        case GT::MULTIPOLYGON: {
            size_t count = 0;
            for (const auto& poly :
                 static_cast<const mlt::geometry::MultiPolygon&>(geom).getPolygons())
            {
                count += poly.size();
            }
            return count;
        }
        case GT::MULTILINESTRING:
            return static_cast<const mlt::geometry::MultiLineString&>(geom)
                .getLineStrings().size();
        default:
            return 0;
    }
} CATCH_BRIDGE_RET(0)}

size_t mlt_feature_ring_size(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    size_t ringIndex)
{ try {
    using GT = mlt::metadata::tileset::GeometryType;

    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return 0; }
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) { return 0; }

    auto& geom = features[featureIndex].getGeometry();
    size_t idx = 0;

    auto findRing = [&](const auto& rings) -> const mlt::CoordVec* {
        if (ringIndex >= idx + rings.size()) {
            idx += rings.size();
            return nullptr;
        }
        return &rings[ringIndex - idx];
    };

    switch (geom.type) {
        case GT::POLYGON: {
            auto* ring = findRing(
                static_cast<const mlt::geometry::Polygon&>(geom).getRings());
            return ring ? ring->size() : 0;
        }
        case GT::MULTIPOLYGON: {
            for (const auto& poly :
                 static_cast<const mlt::geometry::MultiPolygon&>(geom).getPolygons())
            {
                auto* ring = findRing(poly);
                if (ring) { return ring->size(); }
            }
            return 0;
        }
        case GT::MULTILINESTRING: {
            const auto& lines =
                static_cast<const mlt::geometry::MultiLineString&>(geom)
                    .getLineStrings();
            if (ringIndex < lines.size()) { return lines[ringIndex].size(); }
            return 0;
        }
        default:
            return 0;
    }
} CATCH_BRIDGE_RET(0)}

size_t mlt_feature_ring_coordinates(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    size_t ringIndex,
    float* outX,
    float* outY,
    size_t maxCount)
{ try {
    using GT = mlt::metadata::tileset::GeometryType;

    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return 0; }
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) { return 0; }

    auto& geom = features[featureIndex].getGeometry();
    size_t idx = 0;
    size_t written = 0;

    auto writeRing = [&](const mlt::CoordVec& coords) {
        if (ringIndex != idx++) { return; }
        for (const auto& c : coords) {
            if (written >= maxCount) { break; }
            if (outX) { outX[written] = c.x; }
            if (outY) { outY[written] = c.y; }
            written++;
        }
    };

    switch (geom.type) {
        case GT::POLYGON:
            for (const auto& ring :
                 static_cast<const mlt::geometry::Polygon&>(geom).getRings())
            {
                writeRing(ring);
            }
            break;
        case GT::MULTIPOLYGON:
            for (const auto& poly :
                 static_cast<const mlt::geometry::MultiPolygon&>(geom).getPolygons())
            {
                for (const auto& ring : poly) {
                    writeRing(ring);
                }
            }
            break;
        case GT::MULTILINESTRING: {
            const auto& lines =
                static_cast<const mlt::geometry::MultiLineString&>(geom)
                    .getLineStrings();
            for (const auto& line : lines) {
                writeRing(line);
            }
            break;
        }
        default:
            break;
    }

    return written;
} CATCH_BRIDGE_RET(0)}

size_t mlt_feature_polygon_count(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return 0; }
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) { return 0; }
    auto& geom = features[featureIndex].getGeometry();
    using GT = mlt::metadata::tileset::GeometryType;
    if (geom.type != GT::MULTIPOLYGON) { return 0; }
    return static_cast<const mlt::geometry::MultiPolygon&>(geom)
        .getPolygons().size();
} CATCH_BRIDGE_RET(0)}

size_t mlt_feature_polygon_ring_count(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    size_t polygonIndex)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return 0; }
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) { return 0; }
    auto& geom = features[featureIndex].getGeometry();
    using GT = mlt::metadata::tileset::GeometryType;
    if (geom.type != GT::MULTIPOLYGON) { return 0; }
    const auto& polygons =
        static_cast<const mlt::geometry::MultiPolygon&>(geom).getPolygons();
    if (polygonIndex >= polygons.size()) { return 0; }
    return polygons[polygonIndex].size();
} CATCH_BRIDGE_RET(0)}

// MARK: - Properties

size_t mlt_layer_property_key_count(
    MLTTileHandle tile,
    size_t layerIndex)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return 0; }
    return layers[layerIndex].getProperties().size();
} CATCH_BRIDGE_RET(0)}

const char* mlt_layer_property_key(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t keyIndex)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) { return nullptr; }
    const auto& props = layers[layerIndex].getProperties();
    if (keyIndex >= props.size()) { return nullptr; }

    auto it = props.begin();
    std::advance(it, keyIndex);
    return it->first.c_str();
} CATCH_BRIDGE_RET(nullptr)}

// MARK: - Property value access

static const mlt::PresentProperties* findPropertyColumn(
    const mlt::Layer& layer,
    const char* key)
{
    const auto& props = layer.getProperties();
    auto it = props.find(key);
    if (it == props.end()) { return nullptr; }
    return &it->second;
}

int64_t mlt_feature_property_int(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    const char* key,
    bool* found)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex < layers.size()) {
        auto* col = findPropertyColumn(layers[layerIndex], key);
        if (col) {
            auto prop = col->getProperty(static_cast<uint32_t>(featureIndex));
            if (prop.has_value()) {
                auto& p = prop.value();
                if (std::holds_alternative<std::int32_t>(p)) {
                    if (found) { *found = true; }
                    return static_cast<int64_t>(std::get<std::int32_t>(p));
                }
                if (std::holds_alternative<std::int64_t>(p)) {
                    if (found) { *found = true; }
                    return std::get<std::int64_t>(p);
                }
                if (std::holds_alternative<std::uint32_t>(p)) {
                    if (found) { *found = true; }
                    return static_cast<int64_t>(std::get<std::uint32_t>(p));
                }
                if (std::holds_alternative<std::uint64_t>(p)) {
                    if (found) { *found = true; }
                    return static_cast<int64_t>(std::get<std::uint64_t>(p));
                }
                // float/double are intentionally excluded — handled below.
            }
        }
    }
    if (found) { *found = false; }
    return 0;
} CATCH_BRIDGE_RET(0)}

double mlt_feature_property_double(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    const char* key,
    bool* found)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex < layers.size()) {
        auto* col = findPropertyColumn(layers[layerIndex], key);
        if (col) {
            auto prop = col->getProperty(static_cast<uint32_t>(featureIndex));
            if (prop.has_value()) {
                auto& p = prop.value();
                if (std::holds_alternative<double>(p)) {
                    if (found) { *found = true; }
                    return std::get<double>(p);
                }
                if (std::holds_alternative<float>(p)) {
                    if (found) { *found = true; }
                    return static_cast<double>(std::get<float>(p));
                }
                // integer types are intentionally excluded — handled above.
            }
        }
    }
    if (found) { *found = false; }
    return 0.0;
} CATCH_BRIDGE_RET(0.0)}

const char* mlt_feature_property_string(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    const char* key,
    bool* found)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex < layers.size()) {
        auto* col = findPropertyColumn(layers[layerIndex], key);
        if (col) {
            auto prop = col->getProperty(static_cast<uint32_t>(featureIndex));
            if (prop.has_value()) {
                auto& p = prop.value();
                if (std::holds_alternative<std::string_view>(p)) {
                    auto sv = std::get<std::string_view>(p);
                    // Return a null-terminated copy. Freed by Swift via free().
                    auto* buf = static_cast<char*>(std::malloc(sv.size() + 1));
                    if (buf) {
                        std::memcpy(buf, sv.data(), sv.size());
                        buf[sv.size()] = '\0';
                    }
                    if (found) { *found = true; }
                    return buf;
                }
            }
        }
    }
    if (found) { *found = false; }
    return nullptr;
} CATCH_BRIDGE_RET(nullptr)}

bool mlt_feature_property_bool(
    MLTTileHandle tile,
    size_t layerIndex,
    size_t featureIndex,
    const char* key,
    bool* found)
{ try {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex < layers.size()) {
        auto* col = findPropertyColumn(layers[layerIndex], key);
        if (col) {
            auto prop = col->getProperty(static_cast<uint32_t>(featureIndex));
            if (prop.has_value()) {
                auto& p = prop.value();
                if (std::holds_alternative<bool>(p)) {
                    if (found) { *found = true; }
                    return std::get<bool>(p);
                }
                if (std::holds_alternative<std::optional<bool>>(p)) {
                    auto opt = std::get<std::optional<bool>>(p);
                    if (opt.has_value()) {
                        if (found) { *found = true; }
                        return opt.value();
                    }
                }
            }
        }
    }
    if (found) { *found = false; }
    return false;
} CATCH_BRIDGE_RET(false)}


// MARK: - Encoder

struct EncoderState {
    mlt::Encoder encoder;
    std::vector<mlt::Encoder::Layer> layers;
    std::vector<mlt::Encoder::Feature> currentFeatures;
    std::string currentLayerName;
    uint32_t currentLayerExtent = 4096;
};

MLTEncoderHandle mlt_encoder_create(void) { try {
    auto* state = new EncoderState();
    return static_cast<MLTEncoderHandle>(state);
} CATCH_BRIDGE_RET(nullptr)}

void mlt_encoder_destroy(MLTEncoderHandle encoder) { try {
    delete static_cast<EncoderState*>(encoder);
} CATCH_BRIDGE_VOID}

void mlt_encoder_begin_layer(
    MLTEncoderHandle encoder,
    const char* name,
    uint32_t extent)
{ try {
    auto* state = static_cast<EncoderState*>(encoder);
    if (!state->currentLayerName.empty()) {
        state->layers.push_back({
            state->currentLayerName,
            state->currentLayerExtent,
            std::move(state->currentFeatures)});
        state->currentFeatures.clear();
    }
    state->currentLayerName = name ? name : "";
    state->currentLayerExtent = extent;
} CATCH_BRIDGE_VOID}

static mlt::Encoder::PropertyValue typedPropertyFromString(
    int32_t type,
    const std::string& value)
{
    char* end = nullptr;
    switch (type) {
        case kMLTPropString:
            return value;
        case kMLTPropInt: {
            auto v = static_cast<int64_t>(std::strtoll(value.c_str(), &end, 10));
            return v;
        }
        case kMLTPropUInt: {
            auto v = static_cast<uint64_t>(std::strtoull(value.c_str(), &end, 10));
            return v;
        }
        case kMLTPropDouble:
            return std::strtod(value.c_str(), nullptr);
        case kMLTPropFloat:
            return static_cast<float>(std::strtof(value.c_str(), nullptr));
        case kMLTPropBool:
            return (value == "true" || value == "1");
        default:
            return value;
    }
}

static mlt::Encoder::Geometry geometryFromCoords(
    const float* xs,
    const float* ys,
    size_t count,
    int32_t geomType,
    const uint32_t* partSizes,
    size_t partCount,
    const uint32_t* polygonRingCounts,
    size_t polygonCount)
{
    using GT = mlt::metadata::tileset::GeometryType;
    mlt::Encoder::Geometry geom;
    geom.type = static_cast<GT>(geomType);

    if (geomType == kMLTGeometryMultiPolygon && polygonRingCounts) {
        // MultiPolygon: build one part per polygon, with ring sizes.
        geom.partRingSizes.reserve(polygonCount);
        size_t ringIdx = 0;
        size_t coordOffset = 0;
        for (size_t poly = 0; poly < polygonCount; poly++) {
            auto nRings = static_cast<size_t>(polygonRingCounts[poly]);
            std::vector<std::uint32_t> ringSizes;
            ringSizes.reserve(nRings);
            std::vector<mlt::Encoder::Vertex> polyVerts;
            for (size_t r = 0; r < nRings && ringIdx < partCount; r++, ringIdx++) {
                auto ringSize = static_cast<size_t>(partSizes[ringIdx]);
                ringSizes.push_back(static_cast<uint32_t>(ringSize));
                for (size_t i = 0; i < ringSize && coordOffset < count; i++, coordOffset++) {
                    polyVerts.push_back({
                        static_cast<int32_t>(xs[coordOffset]),
                        static_cast<int32_t>(ys[coordOffset])});
                }
            }
            geom.partRingSizes.push_back(std::move(ringSizes));
            geom.parts.push_back(std::move(polyVerts));
        }
    }
    else if (geomType == kMLTGeometryPolygon && partSizes) {
        // Polygon: each part is one ring; build ringSizes + flatten into coordinates.
        geom.ringSizes.reserve(partCount);
        geom.coordinates.reserve(count);
        size_t offset = 0;
        for (size_t p = 0; p < partCount; p++) {
            auto ringSize = static_cast<size_t>(partSizes[p]);
            geom.ringSizes.push_back(partSizes[p]);
            for (size_t i = 0; i < ringSize && offset < count; i++, offset++) {
                geom.coordinates.push_back({
                    static_cast<int32_t>(xs[offset]),
                    static_cast<int32_t>(ys[offset])});
            }
        }
    }
    else if (geomType == kMLTGeometryMultiLineString && partSizes) {
        // MultiLineString: one part per line.
        geom.parts.reserve(partCount);
        size_t offset = 0;
        for (size_t p = 0; p < partCount; p++) {
            auto partSize = static_cast<size_t>(partSizes[p]);
            std::vector<mlt::Encoder::Vertex> part;
            part.reserve(partSize);
            for (size_t i = 0; i < partSize && offset < count; i++, offset++) {
                part.push_back({
                    static_cast<int32_t>(xs[offset]),
                    static_cast<int32_t>(ys[offset])});
            }
            geom.parts.push_back(std::move(part));
        }
    }
    else {
        // Simple geometry: flat coordinate array.
        geom.coordinates.reserve(count);
        for (size_t i = 0; i < count; i++) {
            geom.coordinates.push_back({
                static_cast<int32_t>(xs[i]),
                static_cast<int32_t>(ys[i])});
        }
    }

    return geom;
}

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
    size_t propCount)
{ try {
    auto* state = static_cast<EncoderState*>(encoder);
    mlt::Encoder::Feature feat;
    if (hasId) { feat.id = featureId; }
    feat.geometry = geometryFromCoords(
        xs, ys, coordCount, geomType,
        partSizes, partCount,
        polygonRingCounts, polygonCount);
    for (size_t i = 0; i < propCount; i++) {
        if (props[i].key && props[i].value) {
            feat.properties[props[i].key] =
                typedPropertyFromString(props[i].type, props[i].value);
        }
    }
    state->currentFeatures.push_back(std::move(feat));
} CATCH_BRIDGE_VOID}

uint8_t* mlt_encoder_finish(
    MLTEncoderHandle encoder,
    size_t* outLength)
{ try {
    auto* state = static_cast<EncoderState*>(encoder);
    if (!state->currentLayerName.empty()) {
        state->layers.push_back({
            state->currentLayerName,
            state->currentLayerExtent,
            std::move(state->currentFeatures)});
        state->currentFeatures.clear();
        state->currentLayerName.clear();
    }
    auto result = state->encoder.encode(state->layers);
    auto* buffer = static_cast<uint8_t*>(std::malloc(result.size()));
    std::memcpy(buffer, result.data(), result.size());
    *outLength = result.size();
    state->layers.clear();
    return buffer;
} CATCH_BRIDGE_RET(nullptr)}

void mlt_buffer_free(uint8_t* buffer) { try {
    std::free(buffer);
} CATCH_BRIDGE_VOID}
