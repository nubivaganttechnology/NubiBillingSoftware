import Foundation
import PDFKit
import AppKit
let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let output = CommandLine.arguments[2]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
var combined = ""
for i in 0..<doc.pageCount {
  let page = doc.page(at: i)!
  let text = page.string ?? ""
  precondition(text.contains("Report Scope:"), "Scope header missing on page \(i+1)")
  precondition(text.contains("DISPOSABLE TEST FIXTURE"), "Fixture label missing on page \(i+1)")
  let bounds = page.bounds(for: .mediaBox)
  precondition(abs(bounds.width - 595.28) < 1 && abs(bounds.height - 841.89) < 1, "Not A4")
  combined += "\n--- PAGE \(i+1) ---\n" + text
  let image = page.thumbnail(of: NSSize(width: 1100, height: 1556), for: .mediaBox)
  let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
  try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/page-\(i+1).png"))
}
let normalized = combined.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
for i in 0..<180 { precondition(normalized.contains("EVIDENCE-\(i)"), "Missing evidence row \(i)") }
precondition(!combined.contains("AUDITOR'S STATUTORY OPINION"))
precondition(!combined.contains("Ready for Instant Filing"))
try combined.write(toFile: "\(output)/extracted.txt", atomically: true, encoding: .utf8)
for group in 0..<((doc.pageCount + 8) / 9) {
  let count = min(9, doc.pageCount - group * 9)
  let height = ((count + 2) / 3) * 350
  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 750, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  NSColor.white.setFill(); NSRect(x:0,y:0,width:750,height:height).fill()
  for j in 0..<count {
    let page = doc.page(at: group * 9 + j)!
    let thumb = page.thumbnail(of: NSSize(width: 240, height: 330), for: .mediaBox)
    let x = (j % 3) * 250
    let y = height - (j / 3 + 1) * 350 + 12
    thumb.draw(in: NSRect(x:x+5,y:y,width:240,height:330))
    ("Page \(group*9+j+1)" as NSString).draw(at: NSPoint(x:x+8,y:y-10), withAttributes:[.font:NSFont.systemFont(ofSize:9),.foregroundColor:NSColor.black])
  }
  NSGraphicsContext.restoreGraphicsState()
  try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/contact-\(group+1).png"))
}
print("PASS: \(doc.pageCount) A4 pages, repeated scope/fixture labels, all 180 evidence rows, no certification claims")
