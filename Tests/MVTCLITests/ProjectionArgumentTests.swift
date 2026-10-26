@testable import MVTCLI
import GISTools
import Testing

struct ProjectionArgumentTests {

    @Test
    func parsesCommonAliases() {
        #expect(ProjectionArgument(argument: "auto")?.projection == nil)
        #expect(ProjectionArgument(argument: "4326")?.projection == .epsg4326)
        #expect(ProjectionArgument(argument: "epsg4326")?.projection == .epsg4326)
        #expect(ProjectionArgument(argument: "EPSG:3857")?.projection == .epsg3857)
        #expect(ProjectionArgument(argument: "SRID=4978")?.projection == .epsg4978)
        #expect(ProjectionArgument(argument: "urn:ogc:def:crs:EPSG::3857")?.projection == .epsg3857)
        #expect(ProjectionArgument(argument: "noSRID")?.projection == .noSRID)
        #expect(ProjectionArgument(argument: "none")?.projection == .noSRID)
    }

    @Test
    func parsesWKT() {
        let wkt = #"GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]]"#
        #expect(ProjectionArgument(argument: wkt)?.projection == .epsg4326)
    }

    @Test
    func rejectsUnknownValues() {
        #expect(ProjectionArgument(argument: "not-a-crs") == nil)
        #expect(ProjectionArgument(argument: "EPSG:not-a-number") == nil)
        #expect(ProjectionArgument(argument: "") == nil)
    }

}
