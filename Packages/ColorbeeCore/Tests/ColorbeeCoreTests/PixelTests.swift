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
