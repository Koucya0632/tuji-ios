// Mascot placeholder — SF Symbols stand in for the 6 poses until the real
// PDFs arrive from design. Each pose has a distinct symbol so screen
// layouts can be validated without the real artwork.
//
// When the PDFs land, replace this body with:
//   Image("mascot-\(pose.rawValue)").resizable().aspectRatio(contentMode: .fit)
// and the rest of the codebase keeps working (same API).

import SwiftUI

enum MascotPose: String, CaseIterable {
    case face, wave, think, cheer, sleep, peek
}

struct Mascot: View {
    let pose: MascotPose
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().fill(.tujiTealSoft)
            Image(systemName: symbolName)
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(.tujiTeal)
        }
        .frame(width: size, height: size)
    }

    private var symbolName: String {
        switch pose {
        case .face: "cat.fill"
        case .wave: "hand.wave.fill"
        case .think: "questionmark.bubble.fill"
        case .cheer: "star.fill"
        case .sleep: "moon.zzz.fill"
        case .peek: "eyes"
        }
    }
}

#Preview {
    HStack(spacing: Space.s3) {
        ForEach(MascotPose.allCases, id: \.self) { pose in
            VStack {
                Mascot(pose: pose)
                Text(pose.rawValue).font(.tujiCaption)
            }
        }
    }
    .padding()
    .background(.tujiBg)
}
