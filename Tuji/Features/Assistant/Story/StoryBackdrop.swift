// 情境故事 — the place behind the stage. One flat drawing per scene id from
// the offer (`supermarket`, `office`, `restaurant`, `station`, `home`), made of
// the app's own colour tokens rather than painted art, so it sits with 紙與墨.
// An id the app does not know yet (the server owns the list) gets a plain
// room. Placeholder art for the prototype: swap a case for an asset image
// when the illustrations exist.
//
// Everything is laid out against `floor`, the fraction of the height where
// the wall meets the ground; the stage stands Moira on it.

import SwiftUI

struct StoryBackdrop: View {
    let sceneId: String?

    /// Where the wall meets the floor, as a fraction of the height.
    static let floor: CGFloat = 0.62

    var body: some View {
        Canvas { context, size in
            let floorY = size.height * Self.floor
            var painter = Painter(
                context: context,
                wall: CGRect(x: 0, y: 0, width: size.width, height: floorY),
                ground: CGRect(x: 0, y: floorY, width: size.width, height: size.height - floorY)
            )
            switch self.sceneId {
            case "supermarket": painter.supermarket()
            case "office": painter.office()
            case "restaurant": painter.restaurant()
            case "station": painter.station()
            default: painter.home()
            }
        }
        .accessibilityHidden(true)
    }
}

/// Draws one scene. `wall` and `ground` split the canvas at the floor line;
/// positions are fractions of the wall so every scene scales with the stage.
private struct Painter {
    var context: GraphicsContext
    let wall: CGRect
    let ground: CGRect

    private var w: CGFloat {
        self.wall.width
    }

    private var h: CGFloat {
        self.wall.height
    }

    /// A rectangle in wall fractions.
    private func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: self.w * x, y: self.h * y, width: self.w * width, height: self.h * height)
    }

    private mutating func fill(_ rect: CGRect, _ color: Color) {
        self.context.fill(Path(rect), with: .color(color))
    }

    private mutating func oval(_ rect: CGRect, _ color: Color) {
        self.context.fill(Path(ellipseIn: rect), with: .color(color))
    }

    private mutating func frame(_ rect: CGRect, _ width: CGFloat) {
        self.context.stroke(Path(rect), with: .color(.tujiInk), lineWidth: width)
    }

    // MARK: - Scenes

    mutating func supermarket() {
        self.fill(self.wall, .tujiPaper2)
        self.fill(self.ground, .tujiPaper3)
        self.tiles(every: 48)
        // Two shelving units, three shelves each, stocked with boxes.
        let goods: [Color] = [.tujiBrandPrimary, .tujiAccumulation, .tujiAlert.opacity(0.7), .tujiAccumulationSoft]
        for (index, x) in [0.04, 0.56].enumerated() {
            let unit = self.box(x, 0.18, 0.40, 0.82)
            self.fill(unit, .tujiBrandSecondary.opacity(0.85))
            for row in 0..<3 {
                let shelfY = unit.minY + unit.height * (0.30 + CGFloat(row) * 0.32)
                self.fill(CGRect(x: unit.minX, y: shelfY, width: unit.width, height: 4), .tujiInk)
                let boxW = unit.width / 6
                for slot in 0..<5 {
                    let boxH = unit.height * (0.12 + 0.04 * CGFloat((slot + row + index) % 3))
                    let boxX = unit.minX + boxW * 0.4 + CGFloat(slot) * boxW * 1.08
                    let color = goods[(slot + row * 2 + index) % goods.count]
                    self.fill(CGRect(x: boxX, y: shelfY - boxH, width: boxW * 0.82, height: boxH), color)
                }
            }
        }
    }

    mutating func office() {
        self.fill(self.wall, .tujiAccumulationSoft)
        self.fill(self.ground, .tujiPaper3)
        // A row of windows with towers behind.
        for col in 0..<3 {
            let pane = self.box(0.06 + CGFloat(col) * 0.30, 0.10, 0.26, 0.50)
            self.fill(pane, .tujiPaper)
            for tower in 0..<2 {
                let towerH = pane.height * (0.45 + 0.2 * CGFloat((col + tower) % 2))
                let towerX = pane.minX + pane.width * (0.12 + 0.46 * CGFloat(tower))
                let rect = CGRect(x: towerX, y: pane.maxY - towerH, width: pane.width * 0.28, height: towerH)
                self.fill(rect, .tujiAccumulation.opacity(0.35))
            }
            self.frame(pane, 3)
            self.fill(CGRect(x: pane.midX - 1.5, y: pane.minY, width: 3, height: pane.height), .tujiInk)
        }
        // Desk with a monitor.
        let desk = self.box(0.52, 0.92, 0.44, 0.08)
        self.fill(desk, .tujiBrandSecondary)
        let screen = CGRect(
            x: desk.minX + desk.width * 0.30,
            y: desk.minY - self.h * 0.20,
            width: desk.width * 0.42,
            height: self.h * 0.17
        )
        self.fill(screen, .tujiInk)
        self.fill(screen.insetBy(dx: 4, dy: 4), .tujiAccumulation)
        self.fill(CGRect(x: screen.midX - 3, y: screen.maxY, width: 6, height: desk.minY - screen.maxY), .tujiInk)
        self.plant(at: CGPoint(x: self.w * 0.10, y: self.wall.maxY), height: self.h * 0.26)
    }

    mutating func restaurant() {
        self.fill(self.wall, .tujiBrandPrimary.opacity(0.28))
        self.fill(self.box(0, 0.62, 1, 0.38), .tujiBrandSecondary.opacity(0.75))
        self.fill(self.ground, .tujiBrandSecondary.opacity(0.45))
        self.tiles(every: 64)
        // Pendant lamps.
        for x in [0.2, 0.5, 0.8] {
            let cx = self.w * x
            self.fill(CGRect(x: cx - 1, y: 0, width: 2, height: self.h * 0.22), .tujiInk)
            var shade = Path()
            shade.move(to: CGPoint(x: cx - 22, y: self.h * 0.30))
            shade.addLine(to: CGPoint(x: cx - 8, y: self.h * 0.22))
            shade.addLine(to: CGPoint(x: cx + 8, y: self.h * 0.22))
            shade.addLine(to: CGPoint(x: cx + 22, y: self.h * 0.30))
            shade.closeSubpath()
            self.context.fill(shade, with: .color(.tujiInk))
            self.oval(CGRect(x: cx - 30, y: self.h * 0.30, width: 60, height: 18), .tujiBrandPrimary.opacity(0.5))
        }
        // Menu board.
        let board = self.box(0.62, 0.36, 0.30, 0.20)
        self.fill(board, .tujiInk)
        for line in 0..<3 {
            let y = board.minY + 12 + CGFloat(line) * board.height * 0.26
            let width = board.width * (0.7 - 0.12 * CGFloat(line))
            self.fill(CGRect(x: board.minX + 10, y: y, width: width, height: 3), .tujiPaper.opacity(0.8))
        }
        // A table in front.
        let top = CGRect(
            x: self.ground.width * 0.58,
            y: self.ground.minY + self.ground.height * 0.10,
            width: self.ground.width * 0.38,
            height: 8
        )
        self.fill(top, .tujiInk)
        self.fill(CGRect(x: top.midX - 3, y: top.maxY, width: 6, height: self.ground.height * 0.30), .tujiInk)
    }

    mutating func station() {
        self.fill(self.wall, .tujiAccumulationSoft)
        // Far platform and the track bed.
        self.fill(self.box(0, 0.66, 1, 0.34), .tujiInk3.opacity(0.6))
        for y in [0.76, 0.90] {
            self.fill(CGRect(x: 0, y: self.h * y, width: self.w, height: 3), .tujiInk2)
        }
        // Canopy roof and pillars.
        self.fill(self.box(0, 0, 1, 0.10), .tujiBrandSecondary)
        for x in [0.08, 0.90] {
            self.fill(CGRect(x: self.w * x, y: self.h * 0.10, width: 8, height: self.h * 0.56), .tujiBrandSecondary)
        }
        // Station sign.
        let sign = self.box(0.28, 0.20, 0.44, 0.14)
        self.fill(sign, .tujiPaper)
        self.frame(sign, 2)
        self.fill(CGRect(x: sign.minX, y: sign.maxY - 6, width: sign.width, height: 6), .tujiAccumulation)
        // Near platform: concrete with the yellow tactile line.
        self.fill(self.ground, .tujiPaper3)
        self.fill(CGRect(x: 0, y: self.ground.minY + 6, width: self.ground.width, height: 10), .tujiBrandPrimary)
        self.fill(CGRect(x: 0, y: self.ground.minY, width: self.ground.width, height: 3), .tujiInk)
    }

    mutating func home() {
        self.fill(self.wall, .tujiPaper)
        self.fill(self.ground, .tujiBrandSecondary.opacity(0.35))
        // Planks.
        for x in stride(from: 0, to: self.ground.width, by: self.ground.width / 6) {
            let plank = CGRect(x: x, y: self.ground.minY, width: 1, height: self.ground.height)
            self.fill(plank, .tujiBrandSecondary.opacity(0.4))
        }
        self.fill(CGRect(x: 0, y: self.wall.maxY - 8, width: self.w, height: 8), .tujiBrandSecondary.opacity(0.6))
        // Window with curtains.
        let window = self.box(0.56, 0.12, 0.34, 0.42)
        self.fill(window, .tujiAccumulationSoft)
        self.frame(window, 3)
        self.fill(CGRect(x: window.midX - 1.5, y: window.minY, width: 3, height: window.height), .tujiInk)
        for x in [window.minX - 10, window.maxX - 12] {
            let curtain = CGRect(x: x, y: window.minY - 6, width: 22, height: window.height + 16)
            self.fill(curtain, .tujiBrandPrimary.opacity(0.7))
        }
        // Sofa.
        let seat = self.box(0.04, 0.84, 0.44, 0.16)
        let back = CGRect(x: seat.minX, y: seat.minY - self.h * 0.12, width: seat.width, height: self.h * 0.14)
        self.fill(back, .tujiAccumulation)
        self.fill(seat, .tujiAccumulationDeep)
        self.plant(at: CGPoint(x: self.w * 0.94, y: self.wall.maxY), height: self.h * 0.30)
    }

    // MARK: - Props

    private mutating func tiles(every step: CGFloat) {
        let rect = self.ground
        for x in stride(from: rect.minX, through: rect.maxX, by: step) {
            self.fill(CGRect(x: x, y: rect.minY, width: 1, height: rect.height), .tujiRule)
        }
        for y in stride(from: rect.minY, through: rect.maxY, by: step / 2) {
            self.fill(CGRect(x: rect.minX, y: y, width: rect.width, height: 1), .tujiRule)
        }
    }

    private mutating func plant(at base: CGPoint, height: CGFloat) {
        let potSize = CGSize(width: height * 0.36, height: height * 0.32)
        let pot = CGRect(origin: CGPoint(x: base.x - height * 0.18, y: base.y - potSize.height), size: potSize)
        for (dx, leaf) in [(-0.16, 0.95), (0.0, 1.1), (0.16, 0.9)] {
            let rect = CGRect(
                x: base.x + height * dx - height * 0.10,
                y: pot.minY - height * leaf * 0.70,
                width: height * 0.20,
                height: height * leaf * 0.75
            )
            self.oval(rect, .tujiAccumulationDeep)
        }
        self.fill(pot, .tujiBrandSecondary)
    }
}
