import Testing
@testable import ColorbeeCore

struct PixelBufferTests {
    @Test func memoryIsReadyForZeroCopyGPUAccess() {
        let buffer = PixelBuffer(width: 3, height: 5)
        #expect(buffer.bytesPerRow == 256)
        #expect(Int(bitPattern: buffer.baseAddress) % PixelBuffer.pageSize == 0)
        #expect(buffer.byteCount % PixelBuffer.pageSize == 0)
        #expect(buffer.byteCount >= buffer.bytesPerRow * buffer.height)
    }

    @Test func startsWithTheFillColor() {
        let buffer = PixelBuffer(width: 4, height: 4, fill: .white)
        #expect(buffer[0, 0] == .white)
        #expect(buffer[3, 3] == .white)
    }

    @Test func fillStaysInsideTheRect() {
        let buffer = PixelBuffer(width: 4, height: 4)
        let red = Pixel(r: 255, g: 0, b: 0)
        buffer.fill(red, in: IntRect(x: 1, y: 1, width: 2, height: 2))
        #expect(buffer[0, 0] == .clear)
        #expect(buffer[1, 1] == red)
        #expect(buffer[2, 2] == red)
        #expect(buffer[3, 3] == .clear)
    }

    @Test func pixelsRoundTripThroughARect() {
        let buffer = PixelBuffer(width: 8, height: 8)
        buffer[2, 3] = Pixel(r: 1, g: 2, b: 3, a: 4)
        buffer[3, 4] = Pixel(r: 5, g: 6, b: 7, a: 8)
        let region = IntRect(x: 2, y: 3, width: 2, height: 2)
        let copied = buffer.pixels(in: region)

        let other = PixelBuffer(width: 8, height: 8)
        other.setPixels(copied, in: region.offsetBy(dx: 4, dy: 0))
        #expect(other[6, 3] == Pixel(r: 1, g: 2, b: 3, a: 4))
        #expect(other[7, 4] == Pixel(r: 5, g: 6, b: 7, a: 8))
    }

    @Test func copyIsIndependent() {
        let buffer = PixelBuffer(width: 2, height: 2, fill: .black)
        let copy = buffer.copy()
        buffer[0, 0] = .white
        #expect(copy[0, 0] == .black)
        #expect(copy.contentHash() != buffer.contentHash())
    }
}

struct PixelBufferMemoryTests {
    @Test func aNewBufferIsUntouchedUntilWritten() {
        let buffer = PixelBuffer(width: 300, height: 200)
        #expect(buffer.isUntouched)
        buffer[10, 10] = .black
        #expect(!buffer.isUntouched)
    }

    @Test func discardedMemoryCanBeTakenBackAndWritten() {
        let buffer = PixelBuffer(width: 300, height: 200, fill: .white)
        let generation = buffer.generation
        buffer.discardContents()
        #expect(buffer.isDiscarded)
        #expect(buffer.generation != generation)
        buffer.reuseContents()
        buffer.fill(.black)
        #expect(!buffer.isDiscarded)
        #expect(buffer[150, 100] == .black)
    }
}
