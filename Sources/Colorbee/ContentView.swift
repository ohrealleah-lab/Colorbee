import ColorbeeCore
import SwiftUI

struct ContentView: View {
    private let canvasColor = Pixel.white

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            Rectangle()
                .fill(Color(
                    red: Double(canvasColor.r) / 255,
                    green: Double(canvasColor.g) / 255,
                    blue: Double(canvasColor.b) / 255
                ))
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .padding(40)
                .shadow(radius: 2)
        }
    }
}
