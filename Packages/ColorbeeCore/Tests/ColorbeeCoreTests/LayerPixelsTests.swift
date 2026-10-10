import Foundation
import Testing
@testable import ColorbeeCore

struct LayerPixelsTests {
    /// Noisy pixels with some runs, so LZ4 has matches to find. 37 wide, so rows are padded in memory.
    private func noisy(width: Int = 37, height: Int = 50, seed: UInt32 = 1) -> PixelBuffer {
        let buffer = PixelBuffer(width: width, height: height)
        var state = seed
        for y in 0..<height {
            for x in 0..<width {
                state = state &* 1664525 &+ 1013904223
                let value = UInt8(truncatingIfNeeded: (x / 5 + y) * 7) &+ UInt8(state >> 30)
                buffer[x, y] = Pixel(r: value, g: value &* 3, b: UInt8(y), a: UInt8(state >> 24))
            }
        }
        return buffer
    }

    private func unpaddedRows(of buffer: PixelBuffer) -> Data {
        var data = Data()
        for y in 0..<buffer.height {
            data.append(Data(bytes: buffer.row(y), count: buffer.width * 4))
        }
        return data
    }

    @Test func piecesComeBackExactly() throws {
        let buffer = noisy()
        let compressed = try #require(try LayerPixels.compress([buffer], pieceBytes: 37 * 4 * 6).first)
        #expect(compressed.pieceRows == 6)
        #expect(compressed.pieces.count == 9)
        #expect(compressed.pieces.reduce(0, +) == compressed.data.count)

        let back = PixelBuffer(width: 37, height: 50)
        try LayerPixels.decompress([LayerPixels.Stored(data: compressed.data, pieceRows: compressed.pieceRows,
                                                       pieces: compressed.pieces, buffer: back)])
        #expect(back.contentHash() == buffer.contentHash())
    }

    /// Versions from before the pieces read a layer as one stream: the joined pieces must be one.
    @Test func joinedPiecesReadAsOneStream() throws {
        let buffer = noisy()
        let compressed = try #require(try LayerPixels.compress([buffer], pieceBytes: 37 * 4 * 6).first)
        let whole = try (compressed.data as NSData).decompressed(using: .lz4) as Data
        #expect(whole == unpaddedRows(of: buffer))
    }

    @Test func layersFromBeforeThePiecesStillComeBack() throws {
        let first = noisy(seed: 1), second = noisy(width: 64, height: 9, seed: 2)
        let old = try [first, second].map { try (unpaddedRows(of: $0) as NSData).compressed(using: .lz4) as Data }
        let backFirst = PixelBuffer(width: 37, height: 50), backSecond = PixelBuffer(width: 64, height: 9)
        try LayerPixels.decompress([LayerPixels.Stored(data: old[0], pieceRows: nil, pieces: nil, buffer: backFirst),
                                    LayerPixels.Stored(data: old[1], pieceRows: nil, pieces: nil, buffer: backSecond)])
        #expect(backFirst.contentHash() == first.contentHash())
        #expect(backSecond.contentHash() == second.contentHash())
    }

    @Test func anEmptyLayerIsntReadAndComesBackClear() throws {
        let empty = PixelBuffer(width: 37, height: 50)
        let compressed = try #require(try LayerPixels.compress([empty], pieceBytes: 37 * 4 * 6).first)
        #expect(empty.isUntouched)
        let back = noisy()
        try LayerPixels.decompress([LayerPixels.Stored(data: compressed.data, pieceRows: compressed.pieceRows,
                                                       pieces: compressed.pieces, buffer: back)])
        #expect(back.contentHash() == PixelBuffer(width: 37, height: 50).contentHash())
    }

    @Test func damagedPiecesAreRefused() throws {
        let buffer = noisy()
        let good = try #require(try LayerPixels.compress([buffer], pieceBytes: 37 * 4 * 6).first)
        func attempt(data: Data? = nil, pieceRows: Int? = nil, pieces: [Int]? = nil) {
            let stored = LayerPixels.Stored(data: data ?? good.data, pieceRows: pieceRows ?? good.pieceRows,
                                            pieces: pieces ?? good.pieces, buffer: PixelBuffer(width: 37, height: 50))
            #expect(throws: ProjectFile.Failure.damaged) { try LayerPixels.decompress([stored]) }
        }
        attempt(pieceRows: 0)
        attempt(pieceRows: 51)
        attempt(pieceRows: 7)
        attempt(pieces: good.pieces.dropLast() + [good.pieces.last! + 1])
        attempt(pieces: [good.data.count])
        var corrupted = good.data
        corrupted.replaceSubrange(0..<12, with: Data(repeating: 0xFF, count: 12))
        attempt(data: corrupted)
        attempt(data: good.data.dropLast(20), pieces: good.pieces.dropLast() + [good.pieces.last! - 20])
    }

    /// A project saved before the pieces opens exactly, and its page is stored in pieces once it's parked again.
    @Test func aProjectFromBeforeThePiecesOpensAndIsStoredInPiecesNextTime() throws {
        let canvas = Canvas(size: IntSize(width: 37, height: 50), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.layers[0].buffer = noisy()
        let old = try Self.storedTheOldWay(canvas)

        #expect(try ProjectFile.decode(old).layers[0].buffer.contentHash() == canvas.layers[0].buffer.contentHash())
        let page = try Page(stored: ProjectFile.StoredPage(project: old, resolution: Page.defaultResolution, thumbnail: nil),
                            history: History(byteBudget: .max))
        try page.unpark()
        #expect(page.canvas.layers[0].buffer.contentHash() == canvas.layers[0].buffer.contentHash())
        try page.park()
        let parked = try #require(page.parked)
        #expect(parked != old)
        #expect(try Self.manifest(of: parked).layers.allSatisfy { $0.pixels == nil || $0.pieces != nil })
        try page.unpark()
        #expect(page.canvas.layers[0].buffer.contentHash() == canvas.layers[0].buffer.contentHash())
    }

    private static func manifest(of project: Data) throws -> ProjectFile.Manifest {
        let lengthStart = project.startIndex + ProjectFile.magic.count
        let length = project[lengthStart..<(lengthStart + 4)].withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        return try JSONDecoder().decode(ProjectFile.Manifest.self, from: project[(lengthStart + 4)..<(lengthStart + 4 + length)])
    }

    /// `canvas` as a project from before the pieces: one LZ4 stream per layer and no piece list.
    private static func storedTheOldWay(_ canvas: Canvas) throws -> Data {
        var manifest = try manifest(of: ProjectFile.encode(canvas))
        var blobs = Data()
        for (index, layer) in canvas.layers.enumerated() where manifest.layers[index].pixels != nil {
            var rows = Data()
            for y in 0..<layer.buffer.height { rows.append(Data(bytes: layer.buffer.row(y), count: layer.buffer.width * 4)) }
            let stream = try (rows as NSData).compressed(using: .lz4) as Data
            manifest.layers[index].pixels = blobs.count..<(blobs.count + stream.count)
            manifest.layers[index].pieceRows = nil
            manifest.layers[index].pieces = nil
            blobs.append(stream)
        }
        let json = try JSONEncoder().encode(manifest)
        var data = ProjectFile.magic
        var length = UInt32(json.count).littleEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(json)
        data.append(blobs)
        return data
    }
}
