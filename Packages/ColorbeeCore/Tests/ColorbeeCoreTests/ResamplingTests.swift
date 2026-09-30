import Testing
@testable import ColorbeeCore

struct ResamplingTests {
    @Test func nearestNeighborKeepsHardPixels() {
        let buffer = PixelBuffer(width: 2, height: 1)
        buffer[0, 0] = .black
        buffer[1, 0] = .white
        let doubled = buffer.resampled(to: IntSize(width: 4, height: 2), using: .nearestNeighbor)
        #expect(doubled[0, 1] == .black)
        #expect(doubled[1, 0] == .black)
        #expect(doubled[2, 0] == .white)
        #expect(doubled[3, 1] == .white)
    }

    @Test func sameSizeReturnsTheOriginal() {
        let buffer = PixelBuffer(width: 3, height: 3)
        #expect(buffer.resampled(to: buffer.size, using: .smooth) === buffer)
    }

    @Test func smoothScalingDoesNotDarkenTowardTransparentPixels() {
        let red = Pixel(r: 255, g: 0, b: 0)
        let buffer = PixelBuffer(width: 8, height: 8)
        buffer.fill(red, in: IntRect(x: 0, y: 0, width: 4, height: 8))
        let scaled = buffer.resampled(to: IntSize(width: 20, height: 20), using: .smooth)
        for y in 0..<20 {
            for x in 0..<20 where scaled[x, y].a > 16 {
                let pixel = scaled[x, y]
                #expect(pixel.r >= 245 && pixel.g <= 10 && pixel.b <= 10, "(\(x), \(y)) = \(pixel)")
            }
        }
    }
}
