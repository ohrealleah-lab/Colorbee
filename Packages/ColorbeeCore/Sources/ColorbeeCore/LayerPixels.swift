import Compression
import Foundation

/// A layer's pixels as a project stores them: rows without padding, LZ4-compressed in pieces of whole rows, so
/// every core can compress and expand a page at once (L15: switching pages on large pages paused the app). Each
/// piece is compressed on its own and the pieces are joined into one ordinary LZ4 stream, which versions from
/// before the pieces read as a whole. Projects from before the pieces have one stream per layer, whose blocks
/// lean on each other, so they're expanded a layer at a time, as they always were.
enum LayerPixels {
    /// About this much uncompressed per piece: enough pieces for every core on a large page, few enough that
    /// compressing each on its own costs almost nothing in size.
    static let pieceBytes = 4 << 20
    /// The end of an LZ4 stream. Every piece but the last drops it, so the joined pieces read as one stream.
    private static let endOfStream = Data("bv4$".utf8)

    struct Compressed {
        var data: Data
        /// Rows in each piece but the last.
        var pieceRows: Int
        /// Each piece's compressed size, in order.
        var pieces: [Int]
    }

    /// Where a layer's compressed pixels are, how they're split, and the buffer they go into.
    struct Stored {
        var data: Data
        var pieceRows: Int?
        var pieces: [Int]?
        var buffer: PixelBuffer
    }

    struct CompressionFailed: Error {}

    /// Compresses every buffer, all pieces of all of them at once. Tests pass a small `pieceBytes`.
    static func compress(_ buffers: [PixelBuffer], pieceBytes: Int = LayerPixels.pieceBytes) throws -> [Compressed] {
        // An empty layer reads as zeros without touching it; reading it would make its memory count as used (parking).
        let untouched = buffers.map(\.isUntouched)
        let rowsPerPiece = buffers.map { min($0.height, max(1, pieceBytes / ($0.width * 4))) }
        let work = buffers.indices.flatMap { index in
            stride(from: 0, to: buffers[index].height, by: rowsPerPiece[index]).map { (buffer: index, firstRow: $0) }
        }
        let pieces = ParallelRows.map(work.count) { item -> Data? in
            let buffer = buffers[work[item].buffer]
            let rows = work[item].firstRow..<min(buffer.height, work[item].firstRow + rowsPerPiece[work[item].buffer])
            let isLast = rows.upperBound == buffer.height
            let rowBytes = buffer.width * 4, count = rows.count * rowBytes
            let source = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
            defer { source.deallocate() }
            if untouched[work[item].buffer] {
                source.initializeMemory(as: UInt8.self, repeating: 0, count: count)
            } else {
                for (offset, y) in rows.enumerated() {
                    (source + offset * rowBytes).copyMemory(from: buffer.row(y), byteCount: rowBytes)
                }
            }
            // LZ4's worst case is a little larger than the input.
            let capacity = count + count / 255 + 64
            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { destination.deallocate() }
            let size = compression_encode_buffer(destination, capacity, source.assumingMemoryBound(to: UInt8.self), count, nil, COMPRESSION_LZ4)
            guard size > endOfStream.count else { return nil }
            let stream = Data(bytes: destination, count: size)
            guard stream.suffix(endOfStream.count) == endOfStream else { return nil }
            return isLast ? stream : stream.dropLast(endOfStream.count)
        }
        var results = buffers.indices.map { Compressed(data: Data(), pieceRows: rowsPerPiece[$0], pieces: []) }
        for (item, piece) in zip(work, pieces) {
            guard let piece else { throw CompressionFailed() }
            results[item.buffer].data.append(piece)
            results[item.buffer].pieces.append(piece.count)
        }
        return results
    }

    /// Expands each layer's pixels into its buffer, all pieces of all layers at once. Throws if any doesn't fit.
    static func decompress(_ layers: [Stored]) throws {
        enum Work {
            case piece(layer: Int, data: Data, rows: Range<Int>, isLast: Bool)
            case whole(layer: Int)
        }
        var work: [Work] = []
        for (index, layer) in layers.enumerated() {
            let height = layer.buffer.height
            guard let pieceRows = layer.pieceRows, let pieces = layer.pieces else {
                work.append(.whole(layer: index))
                continue
            }
            // Sizes from the file are checked before they're used, so a damaged file can't reach outside its data.
            guard pieceRows > 0, pieceRows <= height, pieces.count == (height + pieceRows - 1) / pieceRows,
                  pieces.allSatisfy({ $0 > 0 }), pieces.reduce(0, +) == layer.data.count else { throw ProjectFile.Failure.damaged }
            var offset = layer.data.startIndex
            for (number, size) in pieces.enumerated() {
                let rows = (number * pieceRows)..<min(height, (number + 1) * pieceRows)
                work.append(.piece(layer: index, data: layer.data[offset..<(offset + size)], rows: rows, isLast: number == pieces.count - 1))
                offset += size
            }
        }
        let succeeded = ParallelRows.map(work.count) { item -> Bool in
            switch work[item] {
            case .whole(let index):
                let layer = layers[index]
                guard let raw = try? (layer.data as NSData).decompressed(using: .lz4) as Data,
                      raw.count == layer.buffer.width * layer.buffer.height * 4 else { return false }
                raw.withUnsafeBytes { fill(layer.buffer, rows: 0..<layer.buffer.height, from: $0.baseAddress!) }
                return true
            case .piece(let index, let data, let rows, let isLast):
                let buffer = layers[index].buffer
                let count = rows.count * buffer.width * 4
                let stream = isLast ? data : data + endOfStream
                // One byte to spare: with exactly enough room the decoder stops once it's full and never reads the
                // rest, so damage near the end would go unnoticed.
                let destination = UnsafeMutableRawPointer.allocate(byteCount: count + 1, alignment: 16)
                defer { destination.deallocate() }
                let size = stream.withUnsafeBytes { source in
                    compression_decode_buffer(destination.assumingMemoryBound(to: UInt8.self), count + 1,
                                              source.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_LZ4)
                }
                guard size == count else { return false }
                fill(buffer, rows: rows, from: destination)
                return true
            }
        }
        guard succeeded.allSatisfy({ $0 }) else { throw ProjectFile.Failure.damaged }
    }

    /// Copies unpadded rows into the buffer's rows.
    private static func fill(_ buffer: PixelBuffer, rows: Range<Int>, from source: UnsafeRawPointer) {
        let rowBytes = buffer.width * 4
        for (offset, y) in rows.enumerated() {
            UnsafeMutableRawPointer(buffer.row(y)).copyMemory(from: source + offset * rowBytes, byteCount: rowBytes)
        }
    }
}
