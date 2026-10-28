import Foundation
import Testing
@testable import ColorbeeCore

/// .cube looks (FR-9.7 item 4): reading the file, and looking colors up in it.
struct CubeFileTests {
    /// A .cube file of `size` points a side whose output for each point is `f` of its input (each 0...1).
    private func cube(size: Int, title: String? = nil, header: [String] = [], _ f: (Double, Double, Double) -> (Double, Double, Double)) -> Data {
        var lines = ["# made by a test"] + header
        if let title { lines.append("TITLE \"\(title)\"") }
        lines.append("LUT_3D_SIZE \(size)")
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let step = Double(size - 1)
                    let out = f(Double(r) / step, Double(g) / step, Double(b) / step)
                    lines.append("\(out.0) \(out.1) \(out.2)")
                }
            }
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func look(_ data: Data) throws -> ColorLook {
        try CubeFile.read(data, fallbackName: "File").look
    }

    @Test func itsNameIsTheTitleOrTheFileName() throws {
        #expect(try CubeFile.read(cube(size: 2, title: "Golden Hour") { ($0, $1, $2) }, fallbackName: "gh_v2").name == "Golden Hour")
        #expect(try CubeFile.read(cube(size: 2) { ($0, $1, $2) }, fallbackName: "gh_v2").name == "gh_v2")
    }

    @Test func anIdentityLookChangesNothing() throws {
        let transform = try look(cube(size: 17) { ($0, $1, $2) }).transform
        for r in stride(from: 0, through: 255, by: 5) {
            for g in stride(from: 0, through: 255, by: 3) {
                for b in stride(from: 0, through: 255, by: 7) {
                    let pixel = Pixel(r: UInt8(r), g: UInt8(g), b: UInt8(b), a: 200)
                    #expect(transform(pixel) == pixel)
                }
            }
        }
    }

    @Test func colorsBetweenPointsBlendFromTheTetrahedronAroundThem() throws {
        // With only white at the far corner, tetrahedral blending gives exactly the smallest channel.
        let transform = try look(cube(size: 2) { r, g, b in r == 1 && g == 1 && b == 1 ? (1, 1, 1) : (0, 0, 0) }).transform
        #expect(transform(Pixel(r: 200, g: 100, b: 50)) == Pixel(r: 50, g: 50, b: 50))
        #expect(transform(Pixel(r: 30, g: 220, b: 90)) == Pixel(r: 30, g: 30, b: 30))
        #expect(transform(Pixel(r: 128, g: 128, b: 128)) == Pixel(r: 128, g: 128, b: 128))
        // And a straight-line change, such as swapping channels, comes out exactly.
        let swap = try look(cube(size: 2) { r, g, b in (g, b, r) }).transform
        #expect(swap(Pixel(r: 10, g: 120, b: 250)) == Pixel(r: 120, g: 250, b: 10))
    }

    @Test func amountMixesWithTheOriginal() throws {
        var darker = try look(cube(size: 2) { ($0 / 2, $1 / 2, $2 / 2) })
        darker.amount = 0.5
        #expect(darker.transform(Pixel(r: 200, g: 40, b: 0)) == Pixel(r: 150, g: 30, b: 0))
        // A filter's Intensity sets it.
        let filter = PhotoFilter(name: "Invert", steps: [.look(try look(cube(size: 2) { (1 - $0, 1 - $1, 1 - $2) }))])
        guard case .look(let scaled) = filter.steps(atIntensity: 0.25).first else { Issue.record(); return }
        #expect(scaled.amount == 0.25)
    }

    @Test func aDomainStretchesTheInputs() throws {
        // Inputs from 0 to 2: white is half way along the table.
        let halved = try look(cube(size: 9, header: ["DOMAIN_MIN 0 0 0", "DOMAIN_MAX 2 2 2"]) { ($0, $1, $2) }).transform
        let white = halved(Pixel(r: 255, g: 255, b: 255))
        #expect(abs(Int(white.r) - 128) <= 1 && white.r == white.g && white.g == white.b)
    }

    @Test func otherKeywordsAndBlankLinesAreSkipped() throws {
        var text = String(decoding: cube(size: 2) { ($0, $1, $2) }, as: UTF8.self)
        text = text.replacingOccurrences(of: "LUT_3D_SIZE 2", with: "LUT_3D_SIZE 2\nLUT_IN_VIDEO_RANGE\n\n")
        _ = try look(Data(text.utf8))
    }

    @Test func damagedFilesGiveAPlainMessage() {
        func error(_ text: String) -> CubeFile.ReadError? {
            do { _ = try CubeFile.read(Data(text.utf8), fallbackName: "x"); return nil } catch { return error }
        }
        #expect(error("Hello, this is a text file.") == .damaged)
        #expect(error("LUT_3D_SIZE 2\n0 0 0\n1 0 0") == .damaged)
        #expect(error("LUT_3D_SIZE 2\n" + String(repeating: "0 0 zero\n", count: 8)) == .damaged)
        #expect(error("0 0 0\n1 1 1") == .damaged)
        #expect(error("") == .damaged)
        #expect(error("TITLE \"Curve\"\nLUT_1D_SIZE 2\n0 0 0\n1 1 1") == .oneDimensional)
        #expect(error("LUT_3D_SIZE 200") == .tooLarge)
        #expect(CubeFile.ReadError.oneDimensional.localizedDescription.contains("one-dimensional"))
        // Binary junk.
        #expect((try? CubeFile.read(Data([0xFF, 0xD8, 0x00, 0x13, 0x88]), fallbackName: "x")) == nil)
    }

    @Test func aLookIsSavedInProjectsAndFilterFiles() throws {
        let warm = try look(cube(size: 5) { r, g, b in (min(r * 1.1, 1), g, b * 0.9) })
        let effect = Effect.photo(PhotoEdit(filter: PhotoFilter(name: "Warm", steps: [.look(warm)]), filterIntensity: 60))
        let decoded = try JSONDecoder().decode(Effect.self, from: JSONEncoder().encode(effect))
        #expect(decoded == effect)
        let filter = PhotoFilter(name: "Warm", steps: [.look(warm)])
        #expect(try PhotoFilter.imported(from: filter.exported()) == filter)
        // A damaged table isn't read as a look.
        let json = String(decoding: try JSONEncoder().encode(Effect.look(warm)), as: UTF8.self)
            .replacingOccurrences(of: "\"size\":5", with: "\"size\":6")
        #expect((try? JSONDecoder().decode(Effect.self, from: Data(json.utf8))) == nil)
    }

    @Test func theDisplayUsesTheFineTableForALook() throws {
        let warm = try look(cube(size: 3) { ($0, $1, $2 * 0.8) })
        let edit = PhotoEdit(filter: PhotoFilter(name: "Warm", steps: [.look(warm)]))
        #expect(edit.needsFineColorTable)
        #expect(ColorLookup(.photo(edit))?.size == ColorLookup.fineSize)
    }

    @Test func theTestLooksRead() throws {
        let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../TestImages/Photo Editing/Looks")
        let warm = try CubeFile.read(Data(contentsOf: folder.appending(path: "Warm.cube")), fallbackName: "Warm")
        #expect(warm.name == "Warm" && warm.look.size == 33)
        let gray = warm.look.transform(Pixel(r: 128, g: 128, b: 128))
        #expect(gray.r > 128 && gray.b < 128)
        let identity = try CubeFile.read(Data(contentsOf: folder.appending(path: "Identity.cube")), fallbackName: "Identity")
        #expect(identity.name == "Identity")
        #expect(throws: CubeFile.ReadError.oneDimensional) {
            try CubeFile.read(Data(contentsOf: folder.appending(path: "Curve 1D.cube")), fallbackName: "Curve 1D")
        }
    }
}
