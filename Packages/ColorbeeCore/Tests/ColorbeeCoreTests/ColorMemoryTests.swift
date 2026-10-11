import Testing
@testable import ColorbeeCore

struct ColorMemoryTests {
    private let transform = PhotoAdjustments([.exposure: 25, .shadows: 30, .saturation: 20, .warmth: 15]).colorTransform

    private func pixels(_ count: Int) -> [Pixel] {
        var seed: UInt64 = 7
        return (0..<count).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            // Few distinct colors, so most lookups find a remembered one; alpha varies on its own.
            let color = Int(seed >> 56) % 40
            return Pixel(r: UInt8(color * 6), g: UInt8(255 - color * 5), b: UInt8(color * 3 % 256), a: UInt8(truncatingIfNeeded: seed >> 8))
        }
    }

    @Test func givesTheSameResultAsTheFunctionItRemembers() {
        let memory = ColorMemory(transform)
        for pixel in pixels(5_000) {
            #expect(memory(pixel) == transform(pixel))
        }
    }

    @Test func aRememberedColorKeepsEachPixelsOwnAlpha() {
        let memory = ColorMemory(transform)
        let opaque = memory(Pixel(r: 90, g: 140, b: 200, a: 255))
        let faint = memory(Pixel(r: 90, g: 140, b: 200, a: 30))
        #expect(faint == Pixel(r: opaque.r, g: opaque.g, b: opaque.b, a: 30))
    }

    @Test func sharedByAllCoresMatchesWorkingOutEveryPixel() {
        let input = pixels(200_000)
        let memory = ColorMemory(transform)
        let output = ParallelRows.map(input.count / 1_000) { band in
            input[band * 1_000..<(band + 1) * 1_000].map { memory($0) }
        }.flatMap { $0 }
        #expect(output == input.map(transform))
    }
}
