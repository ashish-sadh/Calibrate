import Testing
@testable import DriftCore

@Suite struct SVGPathParserBoundaryTests {
    @Test func compactSignedCoordinatesParseWithoutSeparatingSpaces() throws {
        let path = try #require(
            SVGPathParser.parse("M-1-2L3.5-4.25C0.5-6 7.25 8 -9.5 10Z")
        )

        #expect(path.commands == [
            .move(x: -1, y: -2),
            .line(x: 3.5, y: -4.25),
            .curve(c1x: 0.5, c1y: -6, c2x: 7.25, c2y: 8, x: -9.5, y: 10),
            .close,
        ])
        #expect(path.bounds == .init(minX: -9.5, minY: -6, maxX: 7.25, maxY: 10))
    }

    @Test func multipleClosedSubpathsContributeToBounds() throws {
        let path = try #require(SVGPathParser.parse("M0 0L2 3ZM10 -4L8 1Z"))

        #expect(path.commands == [
            .move(x: 0, y: 0),
            .line(x: 2, y: 3),
            .close,
            .move(x: 10, y: -4),
            .line(x: 8, y: 1),
            .close,
        ])
        #expect(path.bounds == .init(minX: 0, minY: -4, maxX: 10, maxY: 3))
    }

    @Test func surroundingAndInterCommandSpacesAreIgnored() throws {
        let path = try #require(SVGPathParser.parse("   M1 2   L3 4 Z   "))

        #expect(path.commands == [
            .move(x: 1, y: 2),
            .line(x: 3, y: 4),
            .close,
        ])
    }

    @Test(arguments: [
        "M1",
        "M0 0L2",
        "M0 0C1 2 3 4 5",
        "M1..2 3",
    ])
    func truncatedOrMalformedCoordinatesAreRejected(_ input: String) {
        #expect(SVGPathParser.parse(input) == nil)
    }
}
