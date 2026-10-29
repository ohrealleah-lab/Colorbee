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
    /// (Q11.3). Number lines are read straight from the bytes: a 129-point look has over two million of them, which
    /// took seconds through strings (review V, finding 3).
    public static func read(_ data: Data, fallbackName: String) throws(ReadError) -> (name: String, look: ColorLook) {
        var bytes = [CChar](repeating: 0, count: data.count + 1)
        bytes.withUnsafeMutableBytes { _ = data.copyBytes(to: $0) }
        var title: String?
        var size: Int?
        var domainMin: [Double] = [0, 0, 0], domainMax: [Double] = [1, 1, 1]
        var numbers: [Double] = []
        let result: Result<Void, ReadError> = bytes.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!, end = data.count
            func isSpace(_ c: CChar) -> Bool { c == 0x20 || c == 0x09 }
            func isNewline(_ c: CChar) -> Bool { c == 0x0A || c == 0x0D }
            var i = 0
            while i < end {
                while i < end, isSpace(base[i]) { i += 1 }
                var lineEnd = i
                while lineEnd < end, !isNewline(base[lineEnd]) { lineEnd += 1 }
                defer { i = lineEnd + 1 }
                guard i < lineEnd, base[i] != 0x23 else { continue }
                let first = UInt8(bitPattern: base[i])
                if (0x30...0x39).contains(first) || first == 0x2D || first == 0x2B || first == 0x2E {
                    guard size != nil else { return .failure(.damaged) }
                    // Three numbers, then nothing but spaces.
                    var position = UnsafeMutablePointer(mutating: base + i)
                    for _ in 0..<3 {
                        var next: UnsafeMutablePointer<CChar>?
                        let value = strtod(position, &next)
                        guard let next, next != position, next <= base + lineEnd, value.isFinite else { return .failure(.damaged) }
                        numbers.append(value)
                        position = next
                    }
                    var rest = position - UnsafeMutablePointer(mutating: base)
                    while rest < lineEnd, isSpace(base[rest]) { rest += 1 }
                    guard rest == lineEnd else { return .failure(.damaged) }
                    continue
                }
                let raw = UnsafeRawBufferPointer(start: base + i, count: lineEnd - i)
                let line = (String(bytes: raw, encoding: .utf8) ?? String(bytes: raw, encoding: .isoLatin1) ?? "")
                    .trimmingCharacters(in: .whitespaces)
                let words = line.split(whereSeparator: \.isWhitespace)
                guard !words.isEmpty else { continue }
                do throws(ReadError) {
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
                        numbers.reserveCapacity(n * n * n * 3)
                    case "DOMAIN_MIN":
                        domainMin = try triple(words)
                    case "DOMAIN_MAX":
                        domainMax = try triple(words)
                    case "LUT_3D_INPUT_RANGE":
                        guard words.count == 3, let low = Double(words[1]), let high = Double(words[2]) else { throw .damaged }
                        domainMin = [low, low, low]
                        domainMax = [high, high, high]
                    default:
                        // Other keywords some programs add (LUT_IN_VIDEO_RANGE and the like) don't change the table;
                        // "nan" and "inf" aren't numbers a table can hold.
                        if Double(words[0]) != nil { throw .damaged }
                    }
                } catch {
                    return .failure(error)
                }
            }
            return .success(())
        }
        if case .failure(let error) = result { throw error }
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
