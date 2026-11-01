import Testing
@testable import ColorbeeCore

struct PixelTests {
    @Test func isFourBytesWithNoPadding() {
        #expect(MemoryLayout<Pixel>.size == 4)
        #expect(MemoryLayout<Pixel>.stride == 4)
    }

    @Test func storesBytesInBGRAOrder() {
        let pixel = Pixel(r: 0x11, g: 0x22, b: 0x33, a: 0x44)
        let bytes = withUnsafeBytes(of: pixel) { Array($0) }
        #expect(bytes == [0x33, 0x22, 0x11, 0x44])
    }

    @Test func keepsAlphaStraight() {
        let halfRed = Pixel(r: 255, g: 0, b: 0, a: 128)
        #expect(halfRed.r == 255)
        #expect(halfRed.a == 128)
    }
}

/// One gray formula for Desaturate, masks and histograms (review round 11, AD 4).
struct PixelGrayTests {
    @Test func maskGrayIsTheRoundedRec709Luminance() {
        #expect(Pixel(r: 255, g: 0, b: 0).maskGray == Pixel(r: 54, g: 54, b: 54))
        #expect(Pixel(r: 0, g: 255, b: 0, a: 128).maskGray == Pixel(r: 182, g: 182, b: 182, a: 128))
        #expect(Pixel(r: 0, g: 0, b: 255).maskGray == Pixel(r: 18, g: 18, b: 18))
        let pixel = Pixel(r: 200, g: 120, b: 40)
        #expect(Effect.desaturate.pointwise!(pixel) == pixel.maskGray)
    }
}
