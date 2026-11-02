// Disegna l'icona dell'app e scrive un .iconset: swift scripts/make-icon.swift <cartella.iconset>
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // sfondo: squircle con sfumatura blu -> ciano (margine come da linee guida macOS)
    let inset = s * 0.098
    let bg = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = NSBezierPath(roundedRect: bg, xRadius: bg.width * 0.225, yRadius: bg.width * 0.225)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    squircle.fill()
    ctx.restoreGState()
    squircle.addClip()
    NSGradient(colors: [NSColor(red: 0.10, green: 0.30, blue: 0.92, alpha: 1),
                        NSColor(red: 0.12, green: 0.78, blue: 0.90, alpha: 1)])!
        .draw(in: bg, angle: -50)
    // alone luminoso in alto a sinistra
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: bg.minX + bg.width * 0.25, y: bg.maxY - bg.width * 0.1), radius: 0,
              toCenter: NSPoint(x: bg.minX + bg.width * 0.25, y: bg.maxY - bg.width * 0.1), radius: bg.width * 0.7, options: [])

    // scheda SD (coordinate con origine in basso a sinistra)
    let w = s * 0.46, h = w * 1.36
    let card = NSRect(x: (s - w) / 2, y: (s - h) / 2 - s * 0.005, width: w, height: h)
    let r = w * 0.07
    let p = NSBezierPath()
    p.move(to: NSPoint(x: card.minX + r, y: card.maxY))
    p.line(to: NSPoint(x: card.minX + w * 0.66, y: card.maxY))
    p.line(to: NSPoint(x: card.maxX, y: card.maxY - w * 0.34))
    p.line(to: NSPoint(x: card.maxX, y: card.minY + r))
    p.curve(to: NSPoint(x: card.maxX - r, y: card.minY), controlPoint1: NSPoint(x: card.maxX, y: card.minY), controlPoint2: NSPoint(x: card.maxX, y: card.minY))
    p.line(to: NSPoint(x: card.minX + r, y: card.minY))
    p.curve(to: NSPoint(x: card.minX, y: card.minY + r), controlPoint1: NSPoint(x: card.minX, y: card.minY), controlPoint2: NSPoint(x: card.minX, y: card.minY))
    p.line(to: NSPoint(x: card.minX, y: card.maxY - r))
    p.curve(to: NSPoint(x: card.minX + r, y: card.maxY), controlPoint1: NSPoint(x: card.minX, y: card.maxY), controlPoint2: NSPoint(x: card.minX, y: card.maxY))
    p.close()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.05, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    NSColor.white.setFill()
    p.fill()
    ctx.restoreGState()

    ctx.saveGState()
    p.addClip()
    NSGradient(colors: [NSColor(red: 0.90, green: 0.14, blue: 0.32, alpha: 1),
                        NSColor(red: 0.55, green: 0.06, blue: 0.22, alpha: 1)])!
        .draw(in: card, angle: -60)
    ctx.restoreGState()

    // etichetta bianca con frecce circolari (clonazione)
    let label = NSRect(x: card.minX + w * 0.14, y: card.minY + h * 0.36, width: w * 0.72, height: w * 0.50)
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(roundedRect: label, xRadius: w * 0.06, yRadius: w * 0.06).fill()
    let cx = label.midX, cy = label.midY, rad = w * 0.15
    NSColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1).setStroke()
    for (start, end, tipAngle) in [(30.0, 150.0, 150.0), (210.0, 330.0, 330.0)] {
        let arc = NSBezierPath()
        arc.lineWidth = w * 0.045
        arc.lineCapStyle = .round
        arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: rad, startAngle: start, endAngle: end)
        arc.stroke()
        let a = tipAngle * .pi / 180
        let tip = NSPoint(x: cx + rad * cos(a), y: cy + rad * sin(a))
        let dir = a + .pi / 2   // tangente
        let head = NSBezierPath()
        head.lineWidth = w * 0.045
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        let l = w * 0.075
        head.move(to: NSPoint(x: tip.x + l * cos(dir + 2.5), y: tip.y + l * sin(dir + 2.5)))
        head.line(to: NSPoint(x: tip.x + l * 0.2 * cos(dir), y: tip.y + l * 0.2 * sin(dir)))
        head.line(to: NSPoint(x: tip.x + l * cos(dir - 2.5 + .pi), y: tip.y + l * sin(dir - 2.5 + .pi)))
        head.stroke()
    }

    // contatti dorati
    let cw = w * 0.068, gap = w * 0.022
    let total = 8 * cw + 7 * gap
    for i in 0..<8 {
        let rect = NSRect(x: card.midX - total / 2 + CGFloat(i) * (cw + gap), y: card.minY + w * 0.03, width: cw, height: w * 0.17)
        NSGradient(colors: [NSColor(red: 0.98, green: 0.84, blue: 0.45, alpha: 1), NSColor(red: 0.78, green: 0.56, blue: 0.20, alpha: 1)])!
            .draw(in: NSBezierPath(roundedRect: rect, xRadius: cw * 0.2, yRadius: cw * 0.2), angle: -90)
    }

    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("uso: make-icon.swift <cartella.iconset>\n".utf8))
    exit(64)
}
let dir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
