#include "CMLT.h"

#include <mlt/decoder.hpp>
#include <mlt/feature.hpp>
#include <mlt/geometry.hpp>
#include <mlt/layer.hpp>
#include <mlt/properties.hpp>
#include <mlt/tile.hpp>

#include <cstring>
#include <string>
#include <vector>

// MARK: - Decoder

MLTDecoderHandle mlt_decoder_create(bool supportFastPFOR) {
    auto* decoder = new mlt::Decoder(supportFastPFOR);
    return static_cast<MLTDecoderHandle>(decoder);
}

void mlt_decoder_destroy(MLTDecoderHandle decoder) {
    delete static_cast<mlt::Decoder*>(decoder);
}

// MARK: - Tile

MLTTileHandle mlt_tile_decode(MLTDecoderHandle decoder, const uint8_t* data, size_t length) {
    auto* dec = static_cast<mlt::Decoder*>(decoder);
    auto tile = new mlt::MapLibreTile(dec->decode(mlt::DataView(reinterpret_cast<const char*>(data), length)));
    return static_cast<MLTTileHandle>(tile);
}

void mlt_tile_destroy(MLTTileHandle tile) {
    delete static_cast<mlt::MapLibreTile*>(tile);
}

size_t mlt_tile_layer_count(MLTTileHandle tile) {
    return static_cast<mlt::MapLibreTile*>(tile)->getLayers().size();
}

const char* mlt_tile_layer_name(MLTTileHandle tile, size_t layerIndex) {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) return nullptr;
    return layers[layerIndex].getName().c_str();
}

uint32_t mlt_tile_layer_extent(MLTTileHandle tile, size_t layerIndex) {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) return 0;
    return layers[layerIndex].getExtent();
}

size_t mlt_tile_layer_feature_count(MLTTileHandle tile, size_t layerIndex) {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) return 0;
    return layers[layerIndex].getFeatures().size();
}

// MARK: - Feature

bool mlt_feature_has_id(MLTTileHandle tile, size_t layerIndex, size_t featureIndex) {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) return false;
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) return false;
    return features[featureIndex].getID().has_value();
}

uint64_t mlt_feature_id(MLTTileHandle tile, size_t layerIndex, size_t featureIndex) {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) return 0;
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) return 0;
    auto id = features[featureIndex].getID();
    return id.has_value() ? id.value() : 0;
}

int32_t mlt_feature_geometry_type(MLTTileHandle tile, size_t layerIndex, size_t featureIndex) {
    using GT = mlt::metadata::tileset::GeometryType;

    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) return 0;
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) return 0;

    auto& geom = features[featureIndex].getGeometry();
    switch (geom.type) {
        case GT::POINT:             return kMLTGeometryPoint;
        case GT::MULTIPOINT:        return kMLTGeometryMultiPoint;
        case GT::LINESTRING:        return kMLTGeometryLineString;
        case GT::MULTILINESTRING:   return kMLTGeometryMultiLineString;
        case GT::POLYGON:           return kMLTGeometryPolygon;
        case GT::MULTIPOLYGON:      return kMLTGeometryMultiPolygon;
        default:                    return kMLTGeometryUnknown;
    }
}

// MARK: - Coordinate access

static size_t collectCoordinates(const mlt::geometry::Geometry& geom, float* outX, float* outY, size_t maxCount) {
    using GT = mlt::metadata::tileset::GeometryType;
    size_t written = 0;

    auto write = [&](const mlt::CoordVec& coords) {
        for (const auto& c : coords) {
            if (written >= maxCount) return;
            if (outX) outX[written] = c.x;
            if (outY) outY[written] = c.y;
            written++;
        }
    };

    switch (geom.type) {
        case GT::POINT: {
            const auto& pt = static_cast<const mlt::geometry::Point&>(geom);
            if (written < maxCount) {
                if (outX) outX[written] = pt.getCoordinate().x;
                if (outY) outY[written] = pt.getCoordinate().y;
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

size_t mlt_feature_coordinate_count(MLTTileHandle tile, size_t layerIndex, size_t featureIndex) {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) return 0;
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) return 0;
    return collectCoordinates(features[featureIndex].getGeometry(), nullptr, nullptr, SIZE_MAX);
}

size_t mlt_feature_coordinates(MLTTileHandle tile, size_t layerIndex, size_t featureIndex,
                                float* outX, float* outY, size_t maxCount) {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) return 0;
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) return 0;
    return collectCoordinates(features[featureIndex].getGeometry(), outX, outY, maxCount);
}

// MARK: - Ring access (for polygon geometries)

size_t mlt_feature_ring_count(MLTTileHandle tile, size_t layerIndex, size_t featureIndex) {
    using GT = mlt::metadata::tileset::GeometryType;

    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) return 0;
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) return 0;

    auto& geom = features[featureIndex].getGeometry();
    switch (geom.type) {
        case GT::POLYGON:
            return static_cast<const mlt::geometry::Polygon&>(geom).getRings().size();
        case GT::MULTIPOLYGON: {
            size_t count = 0;
            for (const auto& poly : static_cast<const mlt::geometry::MultiPolygon&>(geom).getPolygons()) {
                count += poly.size();
            }
            return count;
        }
        default:
            return 0;
    }
}

size_t mlt_feature_ring_size(MLTTileHandle tile, size_t layerIndex, size_t featureIndex, size_t ringIndex) {
    using GT = mlt::metadata::tileset::GeometryType;

    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) return 0;
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) return 0;

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
            auto* ring = findRing(static_cast<const mlt::geometry::Polygon&>(geom).getRings());
            return ring ? ring->size() : 0;
        }
        case GT::MULTIPOLYGON: {
            for (const auto& poly : static_cast<const mlt::geometry::MultiPolygon&>(geom).getPolygons()) {
                auto* ring = findRing(poly);
                if (ring) return ring->size();
            }
            return 0;
        }
        default:
            return 0;
    }
}

size_t mlt_feature_ring_coordinates(MLTTileHandle tile, size_t layerIndex, size_t featureIndex,
                                     size_t ringIndex, float* outX, float* outY, size_t maxCount) {
    using GT = mlt::metadata::tileset::GeometryType;

    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) return 0;
    const auto& features = layers[layerIndex].getFeatures();
    if (featureIndex >= features.size()) return 0;

    auto& geom = features[featureIndex].getGeometry();
    size_t idx = 0;
    size_t written = 0;

    auto writeRing = [&](const mlt::CoordVec& coords) {
        if (ringIndex != idx++) return;
        for (const auto& c : coords) {
            if (written >= maxCount) break;
            if (outX) outX[written] = c.x;
            if (outY) outY[written] = c.y;
            written++;
        }
    };

    switch (geom.type) {
        case GT::POLYGON:
            for (const auto& ring : static_cast<const mlt::geometry::Polygon&>(geom).getRings()) {
                writeRing(ring);
            }
            break;
        case GT::MULTIPOLYGON:
            for (const auto& poly : static_cast<const mlt::geometry::MultiPolygon&>(geom).getPolygons()) {
                for (const auto& ring : poly) {
                    writeRing(ring);
                }
            }
            break;
        default:
            break;
    }

    return written;
}

// MARK: - Properties

size_t mlt_layer_property_key_count(MLTTileHandle tile, size_t layerIndex) {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) return 0;
    return layers[layerIndex].getProperties().size();
}

const char* mlt_layer_property_key(MLTTileHandle tile, size_t layerIndex, size_t keyIndex) {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex >= layers.size()) return nullptr;
    const auto& props = layers[layerIndex].getProperties();
    if (keyIndex >= props.size()) return nullptr;

    auto it = props.begin();
    std::advance(it, keyIndex);
    return it->first.c_str();
}

// MARK: - Property value access

static const mlt::PresentProperties* findPropertyColumn(const mlt::Layer& layer, const char* key) {
    const auto& props = layer.getProperties();
    auto it = props.find(key);
    if (it == props.end()) return nullptr;
    return &it->second;
}

int64_t mlt_feature_property_int(MLTTileHandle tile, size_t layerIndex, size_t featureIndex,
                                  const char* key, bool* found) {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex < layers.size()) {
        auto* col = findPropertyColumn(layers[layerIndex], key);
        if (col) {
            auto prop = col->getProperty(static_cast<uint32_t>(featureIndex));
            if (prop.has_value()) {
                auto& p = prop.value();
                if (std::holds_alternative<std::int32_t>(p)) {
                    if (found) *found = true;
                    return static_cast<int64_t>(std::get<std::int32_t>(p));
                }
                if (std::holds_alternative<std::int64_t>(p)) {
                    if (found) *found = true;
                    return std::get<std::int64_t>(p);
                }
                if (std::holds_alternative<std::uint32_t>(p)) {
                    if (found) *found = true;
                    return static_cast<int64_t>(std::get<std::uint32_t>(p));
                }
                if (std::holds_alternative<std::uint64_t>(p)) {
                    if (found) *found = true;
                    return static_cast<int64_t>(std::get<std::uint64_t>(p));
                }
                if (std::holds_alternative<float>(p)) {
                    if (found) *found = true;
                    return static_cast<int64_t>(std::get<float>(p));
                }
                if (std::holds_alternative<double>(p)) {
                    if (found) *found = true;
                    return static_cast<int64_t>(std::get<double>(p));
                }
            }
        }
    }
    if (found) *found = false;
    return 0;
}

double mlt_feature_property_double(MLTTileHandle tile, size_t layerIndex, size_t featureIndex,
                                    const char* key, bool* found) {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex < layers.size()) {
        auto* col = findPropertyColumn(layers[layerIndex], key);
        if (col) {
            auto prop = col->getProperty(static_cast<uint32_t>(featureIndex));
            if (prop.has_value()) {
                auto& p = prop.value();
                if (std::holds_alternative<double>(p)) {
                    if (found) *found = true;
                    return std::get<double>(p);
                }
                if (std::holds_alternative<float>(p)) {
                    if (found) *found = true;
                    return static_cast<double>(std::get<float>(p));
                }
                if (std::holds_alternative<std::int32_t>(p)) {
                    if (found) *found = true;
                    return static_cast<double>(std::get<std::int32_t>(p));
                }
                if (std::holds_alternative<std::int64_t>(p)) {
                    if (found) *found = true;
                    return static_cast<double>(std::get<std::int64_t>(p));
                }
                if (std::holds_alternative<std::uint32_t>(p)) {
                    if (found) *found = true;
                    return static_cast<double>(std::get<std::uint32_t>(p));
                }
                if (std::holds_alternative<std::uint64_t>(p)) {
                    if (found) *found = true;
                    return static_cast<double>(std::get<std::uint64_t>(p));
                }
            }
        }
    }
    if (found) *found = false;
    return 0.0;
}

const char* mlt_feature_property_string(MLTTileHandle tile, size_t layerIndex, size_t featureIndex,
                                          const char* key, bool* found) {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex < layers.size()) {
        auto* col = findPropertyColumn(layers[layerIndex], key);
        if (col) {
            auto prop = col->getProperty(static_cast<uint32_t>(featureIndex));
            if (prop.has_value()) {
                auto& p = prop.value();
                if (std::holds_alternative<std::string_view>(p)) {
                    auto sv = std::get<std::string_view>(p);
                    // Return a null-terminated copy that lives as long as the tile
                    auto* buf = new char[sv.size() + 1];
                    std::memcpy(buf, sv.data(), sv.size());
                    buf[sv.size()] = '\0';
                    if (found) *found = true;
                    return buf;
                }
            }
        }
    }
    if (found) *found = false;
    return nullptr;
}

bool mlt_feature_property_bool(MLTTileHandle tile, size_t layerIndex, size_t featureIndex,
                                const char* key, bool* found) {
    const auto& layers = static_cast<mlt::MapLibreTile*>(tile)->getLayers();
    if (layerIndex < layers.size()) {
        auto* col = findPropertyColumn(layers[layerIndex], key);
        if (col) {
            auto prop = col->getProperty(static_cast<uint32_t>(featureIndex));
            if (prop.has_value()) {
                auto& p = prop.value();
                if (std::holds_alternative<bool>(p)) {
                    if (found) *found = true;
                    return std::get<bool>(p);
                }
                if (std::holds_alternative<std::optional<bool>>(p)) {
                    auto opt = std::get<std::optional<bool>>(p);
                    if (opt.has_value()) {
                        if (found) *found = true;
                        return opt.value();
                    }
                }
            }
        }
    }
    if (found) *found = false;
    return false;
}
