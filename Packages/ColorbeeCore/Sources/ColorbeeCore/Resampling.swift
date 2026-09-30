import Accelerate

public enum Resampling: Sendable {
    /// Sharp square pixels, for pixel art.
    case nearestNeighbor
    /// Smooth scaling, for photos and screenshots.
    case smooth
}

extension PixelBuffer {
    /// A copy scaled to `size`. Returns `self` unchanged when the size already matches.
    public func resampled(to size: IntSize, using method: Resampling) -> PixelBuffer {
        precondition(size.width > 0 && size.height > 0, "Resampling needs a positive size")
        if size == self.size { return self }
        let result = PixelBuffer(width: size.width, height: size.height)
        switch method {
        case .nearestNeighbor:
            for y in 0..<size.height {
                let sourceRow = row(min(height - 1, y * height / size.height))
                let destination = result.row(y)
                for x in 0..<size.width {
                    destination[x] = sourceRow[min(width - 1, x * width / size.width)]
                }
            }
        case .smooth:
            // Scale premultiplied so transparent pixels don't bleed their color into neighbors.
            // The RGBA8888 variants only care that alpha is last, which holds for BGRA.
            let premultiplied = copy()
            var source = premultiplied.vImageBuffer
            vImagePremultiplyData_RGBA8888(&source, &source, vImage_Flags(kvImageNoFlags))
            var destination = result.vImageBuffer
            vImageScale_ARGB8888(&source, &destination, nil, vImage_Flags(kvImageHighQualityResampling))
            vImageUnpremultiplyData_RGBA8888(&destination, &destination, vImage_Flags(kvImageNoFlags))
        }
        return result
    }

    var vImageBuffer: vImage_Buffer {
        vImage_Buffer(
            data: baseAddress,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: bytesPerRow
        )
    }
}

extension SelectionMask {
    /// The same shape stretched to fill `rect`, sampled nearest-neighbor.
    public func stretched(to rect: IntRect) -> SelectionMask? {
        guard !rect.isEmpty else { return nil }
        if rect.width == bounds.width, rect.height == bounds.height {
            return translatedBy(dx: rect.minX - bounds.minX, dy: rect.minY - bounds.minY)
        }
        var scaled = [UInt8](repeating: 0, count: rect.area)
        for y in 0..<rect.height {
            let sourceRow = min(bounds.height - 1, y * bounds.height / rect.height) * bounds.width
            for x in 0..<rect.width {
                scaled[y * rect.width + x] = values[sourceRow + min(bounds.width - 1, x * bounds.width / rect.width)]
            }
        }
        return SelectionMask(bounds: rect, values: scaled)
    }
}
