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
            let wall = CGRect(x: 0, y: 0, width: size.width, height: floorY)
            let ground = CGRect(x: 0, y: floorY, width: size.width, height: size.height - floorY)
            switch self.sceneId {
            case "supermarket": Self.supermarket(&context, wall: wall, ground: ground)
            case "office": Self.office(&context, wall: wall, ground: ground)
            case "restaurant": Self.restaurant(&context, wall: wall, ground: ground)
            case "station": Self.station(&context, wall: wall, ground: ground)
            default: Self.home(&context, wall: wall, ground: ground)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Scenes

    private static func supermarket(_ c: inout GraphicsContext, wall: CGRect, ground: CGRect) {
        c.fill(Path(wall), with: .color(.tujiPaper2))
        c.fill(Path(ground), with: .color(.tujiPaper3))
        self.tiles(&c, in: ground, every: 48)
        // Two shelving units, three shelves each, stocked with boxes.
        let goods: [Color] = [.tujiBrandPrimary, .tujiAccumulation, .tujiAlert.opacity(0.7), .tujiAccumulationSoft]
        for (index, x) in [0.04, 0.56].enumerated() {
            let unit = CGRect(x: wall.width * x, y: wall.height * 0.18, width: wall.width * 0.40, height: wall.height * 0.82)
            c.fill(Path(unit), with: .color(.tujiBrandSecondary.opacity(0.85)))
            for row in 0 ..< 3 {
                let shelfY = unit.minY + unit.height * (0.30 + CGFloat(row) * 0.32)
                c.fill(Path(CGRect(x: unit.minX, y: shelfY, width: unit.width, height: 4)), with: .color(.tujiInk))
                let boxW = unit.width / 6
                for slot in 0 ..< 5 {
                    let h = unit.height * (0.12 + 0.04 * CGFloat((slot + row + index) % 3))
                    let box = CGRect(x: unit.minX + boxW * 0.4 + CGFloat(slot) * boxW * 1.08, y: shelfY - h, width: boxW * 0.82, height: h)
                    c.fill(Path(box), with: .color(goods[(slot + row * 2 + index) % goods.count]))
                }
            }
        }
        // Hanging sign.
        let sign = CGRect(x: wall.width * 0.04, y: wall.height * 0.04, width: wall.width * 0.28, height: wall.height * 0.09)
        c.fill(Path(sign), with: .color(.tujiBrandPrimary))
        c.stroke(Path(sign), with: .color(.tujiInk), lineWidth: 2)
    }

    private static func office(_ c: inout GraphicsContext, wall: CGRect, ground: CGRect) {
        c.fill(Path(wall), with: .color(.tujiAccumulationSoft))
        c.fill(Path(ground), with: .color(.tujiPaper3))
        // A row of windows with sky and towers behind.
        for col in 0 ..< 3 {
            let w = wall.width * 0.26
            let pane = CGRect(x: wall.width * 0.06 + CGFloat(col) * (w + wall.width * 0.04), y: wall.height * 0.10, width: w, height: wall.height * 0.50)
            c.fill(Path(pane), with: .color(.tujiPaper))
            for tower in 0 ..< 2 {
                let tw = pane.width * 0.28
                let th = pane.height * (0.45 + 0.2 * CGFloat((col + tower) % 2))
                c.fill(Path(CGRect(x: pane.minX + pane.width * (0.12 + 0.46 * CGFloat(tower)), y: pane.maxY - th, width: tw, height: th)),
                       with: .color(.tujiAccumulation.opacity(0.35)))
            }
            c.stroke(Path(pane), with: .color(.tujiInk), lineWidth: 3)
            c.fill(Path(CGRect(x: pane.midX - 1.5, y: pane.minY, width: 3, height: pane.height)), with: .color(.tujiInk))
        }
        // Desk with a monitor.
        let desk = CGRect(x: wall.width * 0.52, y: wall.maxY - wall.height * 0.08, width: wall.width * 0.44, height: wall.height * 0.08)
        c.fill(Path(desk), with: .color(.tujiBrandSecondary))
        let screen = CGRect(x: desk.minX + desk.width * 0.30, y: desk.minY - wall.height * 0.20, width: desk.width * 0.42, height: wall.height * 0.17)
        c.fill(Path(screen), with: .color(.tujiInk))
        c.fill(Path(screen.insetBy(dx: 4, dy: 4)), with: .color(.tujiAccumulation))
        c.fill(Path(CGRect(x: screen.midX - 3, y: screen.maxY, width: 6, height: desk.minY - screen.maxY)), with: .color(.tujiInk))
        self.plant(&c, at: CGPoint(x: wall.width * 0.10, y: wall.maxY), height: wall.height * 0.26)
    }

    private static func restaurant(_ c: inout GraphicsContext, wall: CGRect, ground: CGRect) {
        c.fill(Path(wall), with: .color(.tujiBrandPrimary.opacity(0.28)))
        c.fill(Path(CGRect(x: 0, y: wall.height * 0.62, width: wall.width, height: wall.height * 0.38)), with: .color(.tujiBrandSecondary.opacity(0.75)))
        c.fill(Path(ground), with: .color(.tujiBrandSecondary.opacity(0.45)))
        self.tiles(&c, in: ground, every: 64)
        // Pendant lamps.
        for x in [0.2, 0.5, 0.8] {
            let cx = wall.width * x
            c.fill(Path(CGRect(x: cx - 1, y: 0, width: 2, height: wall.height * 0.22)), with: .color(.tujiInk))
            var shade = Path()
            shade.move(to: CGPoint(x: cx - 22, y: wall.height * 0.30))
            shade.addLine(to: CGPoint(x: cx - 8, y: wall.height * 0.22))
            shade.addLine(to: CGPoint(x: cx + 8, y: wall.height * 0.22))
            shade.addLine(to: CGPoint(x: cx + 22, y: wall.height * 0.30))
            shade.closeSubpath()
            c.fill(shade, with: .color(.tujiInk))
            c.fill(Path(ellipseIn: CGRect(x: cx - 30, y: wall.height * 0.30, width: 60, height: 18)), with: .color(.tujiBrandPrimary.opacity(0.5)))
        }
        // Menu board.
        let board = CGRect(x: wall.width * 0.62, y: wall.height * 0.36, width: wall.width * 0.30, height: wall.height * 0.20)
        c.fill(Path(board), with: .color(.tujiInk))
        for line in 0 ..< 3 {
            c.fill(Path(CGRect(x: board.minX + 10, y: board.minY + 12 + CGFloat(line) * board.height * 0.26, width: board.width * (0.7 - 0.12 * CGFloat(line)), height: 3)),
                   with: .color(.tujiPaper.opacity(0.8)))
        }
        // A table in front.
        let top = CGRect(x: ground.width * 0.58, y: ground.minY + ground.height * 0.10, width: ground.width * 0.38, height: 8)
        c.fill(Path(top), with: .color(.tujiInk))
        c.fill(Path(CGRect(x: top.midX - 3, y: top.maxY, width: 6, height: ground.height * 0.30)), with: .color(.tujiInk))
    }

    private static func station(_ c: inout GraphicsContext, wall: CGRect, ground: CGRect) {
        c.fill(Path(wall), with: .color(.tujiAccumulationSoft))
        // Far platform and the track bed.
        let bed = CGRect(x: 0, y: wall.height * 0.66, width: wall.width, height: wall.height * 0.34)
        c.fill(Path(bed), with: .color(.tujiInk3.opacity(0.6)))
        for y in [0.76, 0.90] {
            c.fill(Path(CGRect(x: 0, y: wall.height * y, width: wall.width, height: 3)), with: .color(.tujiInk2))
        }
        // Canopy pillars and roof.
        c.fill(Path(CGRect(x: 0, y: 0, width: wall.width, height: wall.height * 0.10)), with: .color(.tujiBrandSecondary))
        for x in [0.08, 0.90] {
            c.fill(Path(CGRect(x: wall.width * x, y: wall.height * 0.10, width: 8, height: wall.height * 0.56)), with: .color(.tujiBrandSecondary))
        }
        // Station sign.
        let sign = CGRect(x: wall.midX - wall.width * 0.22, y: wall.height * 0.20, width: wall.width * 0.44, height: wall.height * 0.14)
        c.fill(Path(sign), with: .color(.tujiPaper))
        c.stroke(Path(sign), with: .color(.tujiInk), lineWidth: 2)
        c.fill(Path(CGRect(x: sign.minX, y: sign.maxY - 6, width: sign.width, height: 6)), with: .color(.tujiAccumulation))
        // Near platform: concrete with the yellow tactile line.
        c.fill(Path(ground), with: .color(.tujiPaper3))
        c.fill(Path(CGRect(x: 0, y: ground.minY + 6, width: ground.width, height: 10)), with: .color(.tujiBrandPrimary))
        c.fill(Path(CGRect(x: 0, y: ground.minY, width: ground.width, height: 3)), with: .color(.tujiInk))
    }

    private static func home(_ c: inout GraphicsContext, wall: CGRect, ground: CGRect) {
        c.fill(Path(wall), with: .color(.tujiPaper))
        c.fill(Path(ground), with: .color(.tujiBrandSecondary.opacity(0.35)))
        // Planks.
        for x in stride(from: 0, to: ground.width, by: ground.width / 6) {
            c.fill(Path(CGRect(x: x, y: ground.minY, width: 1, height: ground.height)), with: .color(.tujiBrandSecondary.opacity(0.4)))
        }
        c.fill(Path(CGRect(x: 0, y: wall.maxY - 8, width: wall.width, height: 8)), with: .color(.tujiBrandSecondary.opacity(0.6)))
        // Window with curtains.
        let window = CGRect(x: wall.width * 0.56, y: wall.height * 0.12, width: wall.width * 0.34, height: wall.height * 0.42)
        c.fill(Path(window), with: .color(.tujiAccumulationSoft))
        c.stroke(Path(window), with: .color(.tujiInk), lineWidth: 3)
        c.fill(Path(CGRect(x: window.midX - 1.5, y: window.minY, width: 3, height: window.height)), with: .color(.tujiInk))
        for x in [window.minX - 10, window.maxX - 12] {
            c.fill(Path(CGRect(x: x, y: window.minY - 6, width: 22, height: window.height + 16)), with: .color(.tujiBrandPrimary.opacity(0.7)))
        }
        // Sofa.
        let seat = CGRect(x: wall.width * 0.04, y: wall.maxY - wall.height * 0.16, width: wall.width * 0.44, height: wall.height * 0.16)
        c.fill(Path(CGRect(x: seat.minX, y: seat.minY - wall.height * 0.12, width: seat.width, height: wall.height * 0.14)), with: .color(.tujiAccumulation))
        c.fill(Path(seat), with: .color(.tujiAccumulationDeep))
        self.plant(&c, at: CGPoint(x: wall.width * 0.94, y: wall.maxY), height: wall.height * 0.30)
    }

    // MARK: - Props

    private static func tiles(_ c: inout GraphicsContext, in rect: CGRect, every step: CGFloat) {
        for x in stride(from: rect.minX, through: rect.maxX, by: step) {
            c.fill(Path(CGRect(x: x, y: rect.minY, width: 1, height: rect.height)), with: .color(.tujiRule))
        }
        for y in stride(from: rect.minY, through: rect.maxY, by: step / 2) {
            c.fill(Path(CGRect(x: rect.minX, y: y, width: rect.width, height: 1)), with: .color(.tujiRule))
        }
    }

    private static func plant(_ c: inout GraphicsContext, at base: CGPoint, height: CGFloat) {
        let pot = CGRect(x: base.x - height * 0.18, y: base.y - height * 0.32, width: height * 0.36, height: height * 0.32)
        for (dx, h) in [(-0.16, 0.95), (0.0, 1.1), (0.16, 0.9)] {
            c.fill(Path(ellipseIn: CGRect(x: base.x + height * dx - height * 0.10, y: pot.minY - height * h * 0.70, width: height * 0.20, height: height * h * 0.75)),
                   with: .color(.tujiAccumulationDeep))
        }
        c.fill(Path(pot), with: .color(.tujiBrandSecondary))
    }
}
