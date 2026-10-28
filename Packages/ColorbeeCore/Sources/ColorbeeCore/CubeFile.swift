import Foundation

/// Reads .cube files, the usual format for color looks (Adobe's and Resolve's): an optional TITLE, LUT_3D_SIZE, an
/// optional DOMAIN_MIN and DOMAIN_MAX, then a red, green and blue line for every point, red varying fastest.
public enum CubeFile {
    public enum ReadError: Error, Equatable, LocalizedError {
        /// Not a .cube file, or one cut short or with numbers missing.
        case damaged
        /// A curve for each channel (LUT_1D_SIZE) rather than a color table (Q11.5).
        case oneDimensional
        case tooLarge

        public var errorDescription: String? {
            switch self {
            case .damaged: "This isn't a .cube look Colorbee can read."
            case .oneDimensional: "Colorbee doesn't support one-dimensional .cube files."
            case .tooLarge: "This look is too large."
            }
        }

        public var recoverySuggestion: String? {
            switch self {
            case .damaged: "The file may be damaged, or not a .cube file. Nothing was added."
            case .oneDimensional: "This file holds a curve for each color channel rather than a color table. Choose a 3D look instead. Nothing was added."
            case .tooLarge: "Colorbee takes looks of up to \(ColorLook.sizes.upperBound) points a side. Nothing was added."
            }
        }
    }

    /// The look in `data`, and its name: the TITLE line's, or `fallbackName` (the file's name) when there's none
    /// (Q11.3).
    public static func read(_ data: Data, fallbackName: String) throws(ReadError) -> (name: String, look: ColorLook) {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw .damaged }
        var title: String?
        var size: Int?
        var domainMin: [Double] = [0, 0, 0], domainMax: [Double] = [1, 1, 1]
        var numbers: [Double] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let words = line.split(whereSeparator: \.isWhitespace)
            switch words[0].uppercased() {
            case "TITLE":
                let rest = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                title = rest.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            case "LUT_1D_SIZE":
                throw .oneDimensional
            case "LUT_3D_SIZE":
                guard words.count == 2, let n = Int(words[1]), n >= 2 else { throw .damaged }
                guard n <= ColorLook.sizes.upperBound else { throw .tooLarge }
                size = n
            case "DOMAIN_MIN":
                domainMin = try triple(words)
            case "DOMAIN_MAX":
                domainMax = try triple(words)
            case "LUT_3D_INPUT_RANGE":
                guard words.count == 3, let low = Double(words[1]), let high = Double(words[2]) else { throw .damaged }
                domainMin = [low, low, low]
                domainMax = [high, high, high]
            default:
                // Other keywords some programs add (LUT_IN_VIDEO_RANGE and the like) don't change the table.
                guard Double(words[0]) != nil else { continue }
                guard size != nil else { throw .damaged }
                let values = try triple(words, from: 0)
                numbers.append(contentsOf: values)
            }
        }
        guard let size, numbers.count == size * size * size * 3, zip(domainMin, domainMax).allSatisfy({ $0 < $1 }) else {
            throw .damaged
        }
        let values = numbers.map { UInt16((min(max($0, 0), 1) * 65535).rounded()) }
        var look = ColorLook(size: size, values: values)
        if domainMin != [0, 0, 0] || domainMax != [1, 1, 1] {
            look = resampled(look, domainMin: domainMin, domainMax: domainMax)
        }
        let name = title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        return (name, look)
    }

    private static func triple(_ words: [Substring], from start: Int = 1) throws(ReadError) -> [Double] {
        guard words.count == start + 3 else { throw .damaged }
        var values: [Double] = []
        for word in words[start...] {
            guard let value = Double(word), value.isFinite else { throw .damaged }
            values.append(value)
        }
        return values
    }

    /// A look whose inputs span `domainMin` to `domainMax` rather than 0 to 1, as the same size table over 0 to 1.
    /// Rare; colors outside its domain take its nearest edge.
    private static func resampled(_ look: ColorLook, domainMin: [Double], domainMax: [Double]) -> ColorLook {
        let n = look.size
        let lookUp = look.transform
        var values = [UInt16](repeating: 0, count: look.values.count)
        // Through 8-bit pixels: precise enough for the handful of looks with a domain.
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    func input(_ i: Int, _ c: Int) -> UInt8 {
                        let position = (Double(i) / Double(n - 1) - domainMin[c]) / (domainMax[c] - domainMin[c])
                        return UInt8((min(max(position, 0), 1) * 255).rounded())
                    }
                    let out = lookUp(Pixel(r: input(r, 0), g: input(g, 1), b: input(b, 2)))
                    let index = ((b * n + g) * n + r) * 3
                    values[index] = UInt16(out.r) * 257
                    values[index + 1] = UInt16(out.g) * 257
                    values[index + 2] = UInt16(out.b) * 257
                }
            }
        }
        return ColorLook(size: n, values: values)
    }
}
