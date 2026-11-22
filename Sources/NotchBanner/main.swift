// NotchBanner — Giant 4K Velvet Theater Curtain for the macOS Notch (Swift + Metal + XPBD Cloth)
// Standalone menu-bar app, live 4K info board plugin host, and offscreen Metal cinema demo recorder.

import AppKit
import AVFoundation
import Carbon.HIToolbox
import CoreMedia
import CoreVideo
import ImageIO
import IOKit.ps
import Metal
import MetalKit
import os
import simd
import SwiftUI

// MARK: - Paths & Resource Discovery

enum AppPaths {
    static let configDir: URL = {
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/notch-banner")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static let configURL = configDir.appendingPathComponent("config.json")
    static let boardURL = configDir.appendingPathComponent("board.json")

    static func resource(_ name: String) -> URL {
        // 1. Bundle Resources (.app)
        if let u = Bundle.main.resourceURL?.appendingPathComponent(name), FileManager.default.fileExists(atPath: u.path) {
            return u
        }
        // 2. Sibling Resources/ directory next to executable or project root
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for candidate in [
            exeDir.appendingPathComponent("Resources").appendingPathComponent(name),
            exeDir.deletingLastPathComponent().appendingPathComponent("Resources").appendingPathComponent(name),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources").appendingPathComponent(name),
            configDir.appendingPathComponent(name)
        ] {
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return exeDir.appendingPathComponent("Resources").appendingPathComponent(name)
    }
}

func batteryInfo() -> (Int, Bool)? {
    guard let s = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(s)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for item in list {
        guard let d = IOPSGetPowerSourceDescription(s, item)?.takeUnretainedValue() as? [String: Any],
              let pct = d[kIOPSCurrentCapacityKey as String] as? Int else { continue }
        return (pct, (d[kIOPSIsChargingKey as String] as? Bool) == true || (d[kIOPSPowerSourceStateKey as String] as? String) == kIOPSACPowerValue)
    }
    return nil
}

// MARK: - Enums & Settings

enum BannerLength: Int, CaseIterable {
    case hidden, ultraShort, short, half, full
    var title: String { ["Hide", "Ultra short", "Short", "Half height", "Full height"][rawValue] }
    var shortTitle: String { ["Hide", "Ultra short", "Short", "Half", "Full"][rawValue] }
    func points(notch: CGFloat, available: CGFloat) -> CGFloat {
        switch self {
        case .hidden: return 0
        case .ultraShort: return min(notch + 68, available)
        case .short: return min(notch + 312, available)
        case .half: return (notch + available) * 0.5
        case .full: return available
        }
    }
    func fraction(notch: CGFloat, available: CGFloat) -> Double {
        Double(points(notch: notch, available: available) / max(available, 1))
    }
}

enum BannerDye: Int, CaseIterable {
    case black, garnet, pine, midnight
    var key: String { ["black", "garnet", "pine", "midnight"][rawValue] }
    var title: String { ["Black", "Garnet", "Pine", "Midnight"][rawValue] }
}

enum BannerPrint: Int, CaseIterable {
    case robe, notebook, catenary, lorenz, bifurcation, brachistochrone, silk, board, mesh, mandala, poincare, ink, guilloche, mosaic, waves, sketch, grid
    var key: String { ["robe", "notebook", "catenary", "lorenz", "bifurcation", "brachistochrone", "silk", "board", "mesh", "mandala", "poincare", "ink", "guilloche", "mosaic", "waves", "sketch", "grid"][rawValue] }
    var title: String {
        switch self {
        case .robe: return "Embroidered robe"
        case .notebook: return "Mathematical notebook"
        case .catenary: return "Catenary"
        case .lorenz: return "Lorenz attractor"
        case .bifurcation: return "Period doubling"
        case .brachistochrone: return "Brachistochrone"
        case .silk: return "Teal and gold silk"
        case .board: return "Live 4K info board"
        case .mesh: return "Open net"
        case .grid: return "Grid cloth"
        case .mandala: return "Mandala"
        case .poincare: return "Poincaré grid"
        case .ink: return "Sumi-e ink"
        case .guilloche: return "Guilloché"
        case .mosaic: return "Mosaic"
        case .waves: return "Seigaiha"
        case .sketch: return "Sketch"
        }
    }
    var shortTitle: String {
        switch self {
        case .robe: return "Robe"
        case .notebook: return "Notebook"
        case .lorenz: return "Lorenz"
        case .bifurcation: return "Doubling"
        case .brachistochrone: return "Brachist."
        case .silk: return "Teal Silk"
        case .board: return "Live Board"
        default: return title
        }
    }
    var textureFile: String? {
        switch self {
        case .mesh, .grid, .robe, .silk, .board: return nil
        case .mandala, .poincare, .ink, .guilloche: return "banner-art-plates.png"
        case .mosaic: return "banner-mosaic.png"
        case .waves: return "banner-seigaiha.png"
        case .sketch: return "banner-sketch.png"
        default: return usesPlate ? "banner-plates.png" : "banner-math.png"
        }
    }
    var usesPlate: Bool { (BannerPrint.catenary.rawValue...BannerPrint.brachistochrone.rawValue).contains(rawValue) }
}

enum BannerWidth: String, CaseIterable {
    case notch, wide, half, nearFull = "near-full", full
    var title: String { ["Notch", "Wide", "Half screen", "Near full screen", "Full screen"][Self.allCases.firstIndex(of: self)!] }
    var shortTitle: String { ["Notch", "Wide", "Half", "Near full", "Full"][Self.allCases.firstIndex(of: self)!] }
    func rod(notch: CGFloat, screen: CGFloat) -> CGFloat {
        let base = min(screen, notch + 96)
        switch self {
        case .notch: return base
        case .wide: return max(base, screen * 0.30)
        case .half: return max(base, screen * 0.50)
        case .nearFull: return max(base, screen * 0.85)
        case .full: return screen
        }
    }
    func fraction(notch: CGFloat, screen: CGFloat) -> Double {
        Double(rod(notch: notch, screen: screen) / max(screen, 1))
    }
}

enum BannerCutout: String, CaseIterable {
    case none, swallowtail, pointed, arch, waves
    var title: String {
        switch self {
        case .none: return "Straight (no cutout)"
        case .swallowtail: return "Swallowtail (V-cut)"
        case .pointed: return "Pointed (Pennant)"
        case .arch: return "Arched"
        case .waves: return "Scalloped"
        }
    }
    var shaderId: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

enum StrandSpacing: String, Codable, CaseIterable {
    case coarse, medium, fine, dense, gauze
    var points: Float {
        switch self {
        case .coarse: return 28
        case .medium: return 14
        case .fine: return 7
        case .dense: return 3.5
        case .gauze: return 1.75
        }
    }
}
enum ClothResolution: String, Codable, CaseIterable {
    case auto, coarse, medium, fine, ultra
    func sampling(_ quality: BannerQuality) -> (spacing: Float, limit: Int) {
        switch self {
        case .auto: return (quality.targetSpacing, quality.maxNodes)
        case .coarse: return (22, 2_500)
        case .medium: return (12, 8_000)
        case .fine: return (8, 16_000)
        case .ultra: return (5, 32_000)
        }
    }
}
enum ClothModel: String, Codable, CaseIterable {
    case original, tension
}
enum BannerQuality: String, CaseIterable {
    case low, med, high, xhigh, max, ultra
    var title: String { ["Low", "Med", "High", "XHigh", "Max", "Ultra"][Self.allCases.firstIndex(of: self)!] }
    var targetSpacing: Float {
        switch self {
        case .low: return 28
        case .med: return 20
        case .high: return 14
        case .xhigh: return 11
        case .max: return 9
        case .ultra: return 7
        }
    }
    var maxNodes: Int {
        switch self {
        case .low: return 900
        case .med: return 2_000
        case .high: return 4_800
        case .xhigh: return 7_500
        case .max: return 11_000
        case .ultra: return 16_000
        }
    }
    var substeps: Int {
        switch self {
        case .low, .med: return 2
        case .high: return 3
        case .xhigh, .max: return 4
        case .ultra: return 5
        }
    }
    var iterations: Int {
        switch self {
        case .low, .med, .high, .xhigh: return 2
        case .max, .ultra: return 3
        }
    }
    var fps: Int {
        switch self {
        case .low, .med: return 30
        case .high, .xhigh, .max: return 60
        case .ultra: return 120
        }
    }
    var msaa: Int {
        switch self {
        case .low, .med: return 1
        case .high, .xhigh, .max, .ultra: return 4
        }
    }
    var pixelBudget: CGFloat {
        switch self {
        case .low: return 3_686_400
        case .med: return 6_220_800
        case .high: return 10_500_000
        case .xhigh: return 14_745_600
        case .max: return 18_000_000
        case .ultra: return 24_000_000
        }
    }
}

struct BannerPhysics: Equatable {
    var model: ClothModel = .original
    var resolution: ClothResolution = .auto
    var quality: BannerQuality = .high
    var scale: Float = 1.0
    var mass: Float = 0.85
    var stiffness: Float = 1.0
    var damping: Float = 0.65
    var split = false
    var pleats: Float = 1.0
}

struct BannerConfig: Codable, Equatable {
    var minutes: Double = 5
    var patterns = BannerPrint.allCases.map(\.key)
    var colours = BannerDye.allCases.map(\.key)
    var widths = [BannerWidth.notch, .wide, .half, .nearFull].map(\.rawValue)
    var cutouts = [BannerCutout.none.rawValue]
    var pinnedWeave: String?
    var strandSpacing: StrandSpacing = .fine
    var clothResolution: ClothResolution = .auto
    var clothModel: ClothModel = .original
    var quality = BannerQuality.high.rawValue
    var windStrength: Double = 1.0
    var scale: Double = 1.0
    var mass: Double = 0.85
    var stiffness: Double = 1.0
    var damping: Double = 0.65
    var pleats: Double = 1.0
    var opacity: Double = 1.0
    var widthFraction: Double? = nil
    var heightFraction: Double? = nil
    var offset: Double = 0
    var split = false
    var fadeOnHover: Bool = true
    var hoverOpacity: Double = 0.22
    var topHoverOpacity: Double = 0.08
    var topHoverZone: Double = 115
    static let everyChoices: [(String, Double)] = [("Never", 0), ("1 min", 1), ("5 min", 5), ("15 min", 15), ("30 min", 30), ("1 hour", 60)]

    init() {
        pinnedWeave = BannerPrint.mesh.key
        strandSpacing = .dense
        clothResolution = .fine
        clothModel = .tension
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minutes = try c.decodeIfPresent(Double.self, forKey: .minutes) ?? 5
        patterns = try c.decodeIfPresent([String].self, forKey: .patterns) ?? BannerPrint.allCases.map(\.key)
        colours = try c.decodeIfPresent([String].self, forKey: .colours) ?? BannerDye.allCases.map(\.key)
        widths = try c.decodeIfPresent([String].self, forKey: .widths) ?? [BannerWidth.notch, .wide, .half, .nearFull].map(\.rawValue)
        cutouts = try c.decodeIfPresent([String].self, forKey: .cutouts) ?? [BannerCutout.none.rawValue]
        pinnedWeave = try c.decodeIfPresent(String.self, forKey: .pinnedWeave)
        strandSpacing = StrandSpacing(rawValue: try c.decodeIfPresent(String.self, forKey: .strandSpacing) ?? "") ?? .fine
        clothResolution = ClothResolution(rawValue: try c.decodeIfPresent(String.self, forKey: .clothResolution) ?? "") ?? .auto
        clothModel = ClothModel(rawValue: try c.decodeIfPresent(String.self, forKey: .clothModel) ?? "") ?? .original
        quality = try c.decodeIfPresent(String.self, forKey: .quality) ?? BannerQuality.high.rawValue
        windStrength = try c.decodeIfPresent(Double.self, forKey: .windStrength) ?? 1.0
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        mass = try c.decodeIfPresent(Double.self, forKey: .mass) ?? 0.85
        stiffness = try c.decodeIfPresent(Double.self, forKey: .stiffness) ?? 1.0
        damping = try c.decodeIfPresent(Double.self, forKey: .damping) ?? 0.65
        pleats = try c.decodeIfPresent(Double.self, forKey: .pleats) ?? 1.0
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        widthFraction = try c.decodeIfPresent(Double.self, forKey: .widthFraction)
        heightFraction = try c.decodeIfPresent(Double.self, forKey: .heightFraction)
        offset = min(1, max(-1, try c.decodeIfPresent(Double.self, forKey: .offset) ?? 0))
        split = try c.decodeIfPresent(Bool.self, forKey: .split) ?? false
        fadeOnHover = try c.decodeIfPresent(Bool.self, forKey: .fadeOnHover) ?? true
        hoverOpacity = try c.decodeIfPresent(Double.self, forKey: .hoverOpacity) ?? 0.22
        topHoverOpacity = try c.decodeIfPresent(Double.self, forKey: .topHoverOpacity) ?? 0.08
        topHoverZone = try c.decodeIfPresent(Double.self, forKey: .topHoverZone) ?? 115
    }
    static func load() -> BannerConfig {
        if let d = try? Data(contentsOf: AppPaths.configURL), let f = try? JSONDecoder().decode(BannerConfig.self, from: d) { return f }
        let f = BannerConfig(); f.save(); return f
    }
    func save() {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(self).write(to: AppPaths.configURL, options: .atomic)
    }
    var printPool: [BannerPrint] {
        if pinnedWeave == BannerPrint.mesh.key { return [.mesh] }
        if pinnedWeave == BannerPrint.grid.key { return [.grid] }
        let p = BannerPrint.allCases.filter { patterns.contains($0.key) }; return p.isEmpty ? [.robe] : p }
    var dyePool: [BannerDye] { let p = BannerDye.allCases.filter { colours.contains($0.key) }; return p.isEmpty ? [.garnet] : p }
    var widthPool: [BannerWidth] { let p = BannerWidth.allCases.filter { widths.contains($0.rawValue) }; return p.isEmpty ? [.nearFull] : p }
    var cutoutPool: [BannerCutout] { let p = BannerCutout.allCases.filter { cutouts.contains($0.rawValue) }; return p.isEmpty ? [.none] : p }
    var qualityLevel: BannerQuality { BannerQuality(rawValue: quality) ?? .high }
    var physicsConfig: BannerPhysics {
        BannerPhysics(model: clothModel, resolution: clothResolution, quality: qualityLevel, scale: Float(scale), mass: Float(mass),
                      stiffness: Float(stiffness), damping: Float(damping), split: split, pleats: Float(pleats))
    }
}

struct Rotation<T: Equatable> {
    private var remaining: [T] = []
    private(set) var current: T?
    @discardableResult mutating func advance(_ pool: [T]) -> T {
        remaining = remaining.filter { pool.contains($0) }
        if remaining.isEmpty {
            remaining = pool.shuffled()
            if remaining.count > 1, remaining.last == current { remaining.swapAt(0, remaining.count - 1) }
        }
        let next = remaining.removeLast()
        current = next
        return next
    }
    mutating func keep(_ pool: [T]) -> T {
        if let c = current, pool.contains(c) { return c }
        return advance(pool)
    }
}

// MARK: - XPBD Giant Velvet Cloth Simulation

final class BannerCloth {
    typealias V = SIMD3<Float>
    struct Node {
        var position, previous, normal: V
        let uv: SIMD2<Float>
        var inverseMass: Float
    }
    struct Joint {
        let a, b: Int
        let length, alpha: Float
        var tensionOnly = false
        var lambda: Float = 0
    }
    struct Vertex {
        var position, normal: SIMD4<Float>
        var uv: SIMD2<Float>
    }
    let columns: Int
    let rows: Int
    let aspect: Float
    let widthPoints: Float
    let metersPerWidth: Float
    let heightMeters: Float
    let pointsPerMeter: Float
    let cutout: BannerCutout
    let config: BannerPhysics
    let tail: Float
    var nodes: [Node] = []
    var joints: [Joint] = []
    var indices: [UInt16] = []
    private var visibleNodes: Set<Int>?
    private(set) var topologyVersion = 0
    private var cutTethers = Set<Int>()
    private(set) var grabbed: Int?
    private var triangles: [(Int, Int, Int)] = []
    private var force: [V] = []
    private var rest: [V] = []
    private var maxRestY: Float = 0
    private var vertexScratch: [Vertex] = []
    var wind: Float = 1
    var damping: Float = 0.65
    private(set) var time: Float = 0
    private(set) var liveWindGain: Float = 0
    private(set) var lastStepMs: Double = 0
    struct Brush {
        let a, segment, velocity: SIMD2<Float>
        let lengthSquared: Float
        var remaining: Float
    }
    private var brush: Brush?
    private var gustStart: Float = -20
    private var remainder: Double = 0
    static let outerDt: Float = 1 / 60
    let substeps: Int
    let iterations: Int
    let dt: Float
    static let rodSpan: Float = 0.86
    private var rollAt: Float?
    private var rollSpeed: Float = 0
    private var rollGravity: Float = 0
    private var held: [Bool] = []
    private var looseMass: [Float] = []
    private var start: [V] = []
    var rolling: Bool { rollAt != nil }
    var triangleCount: Int { triangles.count }

    static func cutoutOffset(u: Float, cutout: BannerCutout, tail: Float) -> Float {
        switch cutout {
        case .none: return 0
        case .swallowtail: return tail * (1 - abs(2 * u - 1))
        case .pointed: return tail * abs(2 * u - 1)
        case .arch: return tail * cos((u - 0.5) * Float.pi)
        case .waves: return tail * 0.5 * (1 - cos(6 * Float.pi * u))
        }
    }

    init(aspect: Float, widthPoints: Float = 360, cutout: BannerCutout = .none, config: BannerPhysics = BannerPhysics()) {
        self.aspect = aspect
        self.widthPoints = max(widthPoints, 60)
        self.cutout = cutout
        self.config = config
        self.damping = max(0.1, min(3.0, config.damping))
        self.pointsPerMeter = 115.0 / max(0.4, min(3.0, config.scale))
        self.metersPerWidth = self.widthPoints / self.pointsPerMeter
        let heightPoints = self.widthPoints * aspect
        self.heightMeters = heightPoints / self.pointsPerMeter
        self.substeps = config.quality.substeps
        self.iterations = config.quality.iterations
        self.dt = Self.outerDt / Float(self.substeps)

        let sampling = config.resolution.sampling(config.quality)
        let targetSpacing = sampling.spacing
        let rawCols = max(21, Int((self.widthPoints / targetSpacing).rounded()) + 1)
        let rawRows = max(17, Int((heightPoints / targetSpacing).rounded()) + 1)
        let maxNodes = sampling.limit
        let scale = rawCols * rawRows > maxNodes ? sqrt(Float(maxNodes) / Float(rawCols * rawRows)) : 1.0
        var c = max(19, Int((Float(rawCols) * scale).rounded()))
        if c % 2 == 0 { c += 1 }
        columns = config.split ? c + 1 : c
        rows = max(15, Int((Float(rawRows) * scale).rounded()))
        tail = cutout == .none ? 0 : min(0.21, aspect * 0.28)

        let pleatLambda = min(1.45, max(0.95, 0.90 + 0.035 * metersPerWidth))
        let pleatK = (2 * Float.pi) / pleatLambda
        let pleatAmp = (0.70 / pleatK) * max(0, min(1.8, config.pleats))

        nodes.reserveCapacity(columns * rows)
        rest.reserveCapacity(columns * rows)
        for j in 0..<rows {
            let v = Float(j) / Float(rows - 1)
            for i in 0..<columns {
                let u = Float(i) / Float(columns - 1)
                let yCloth = v * (aspect - Self.cutoutOffset(u: u, cutout: cutout, tail: tail))
                let panelX = config.split ? (u - 0.5) * 0.86 + (i < columns / 2 ? -0.07 : 0.07) : u - 0.5
                let xMeters = panelX * metersPerWidth
                let yMeters = yCloth * metersPerWidth
                let pleat = pleatAmp * (sin(pleatK * xMeters + 0.35) + 0.16 * sin(2 * pleatK * xMeters - 0.7))
                let p = V(xMeters * Self.rodSpan - 0.14 * pleat, yMeters + 0.04 * pleat, pleat)
                nodes.append(Node(position: p, previous: p, normal: V(0, 0, 1), uv: SIMD2(u, yCloth), inverseMass: 0))
                rest.append(V(xMeters, yMeters, 0))
                if yMeters > maxRestY { maxRestY = yMeters }
            }
        }

        let net = config.model == .tension
        let arealDensity = max(0.2, min(2.5, config.mass)) * (net ? 0.52 : 1)
        var mass = [Float](repeating: 0, count: nodes.count)
        triangles.reserveCapacity(2 * (columns - 1) * (rows - 1))
        indices.reserveCapacity(6 * (columns - 1) * (rows - 1))
        func triangle(_ a: Int, _ b: Int, _ c: Int) {
            triangles.append((a, b, c)); indices += [UInt16(a), UInt16(b), UInt16(c)]
            let m = arealDensity * simd_length(simd_cross(rest[b] - rest[a], rest[c] - rest[a])) / 6
            mass[a] += m; mass[b] += m; mass[c] += m
        }
        for j in 0..<(rows - 1) {
            for i in 0..<(columns - 1) {
                let k = j * columns + i
                if config.split && i == columns / 2 - 1 { continue }
                triangle(k, k + 1, k + columns)
                triangle(k + 1, k + columns + 1, k + columns)
            }
        }
        for j in (rows - 2)..<rows where j > 0 {
            let hemBoost: Float = j == rows - 1 ? 1.65 : 1.25
            for i in 0..<columns { mass[j * columns + i] *= hemBoost }
        }
        var sumInvMass: Float = 0
        var freeCount = 0
        for k in columns..<nodes.count {
            let inv = 1 / max(mass[k], 1e-6)
            nodes[k].inverseMass = inv
            sumInvMass += inv
            freeCount += 1
        }
        let avgW2 = 2 * (sumInvMass / Float(max(freeCount, 1)))
        let stiff = max(0.25, min(3.0, config.stiffness))
        let shearAlpha: Float = ((net ? 0.015 : 0.08) / stiff) * avgW2
        let transverseAlpha: Float = net ? (0.7 / stiff) * avgW2 : 0
        let bendHAlpha: Float = (32.0 / stiff) * avgW2
        let bendVAlpha: Float = (18.0 / stiff) * avgW2

        joints.reserveCapacity(nodes.count * 6)
        func link(_ a: Int, _ b: Int, _ alpha: Float, cord: Bool = false) {
            if config.split && (a % columns < columns / 2) != (b % columns < columns / 2) { return }
            joints.append(Joint(a: a, b: b, length: simd_distance(rest[a], rest[b]), alpha: alpha, tensionOnly: cord))
        }
        for j in 0..<rows {
            for i in 0..<columns {
                let k = j * columns + i
                if i + 1 < columns { link(k, k + 1, transverseAlpha) }
                if j + 1 < rows { link(k, k + columns, transverseAlpha) }
                if i + 1 < columns && j + 1 < rows {
                    link(k, k + columns + 1, shearAlpha, cord: net)
                    link(k + 1, k + columns, shearAlpha, cord: net)
                }
                if i + 2 < columns { link(k, k + 2, bendHAlpha) }
                if j + 2 < rows { link(k, k + 2 * columns, bendVAlpha) }
            }
        }
        force = Array(repeating: .zero, count: nodes.count)
        held = Array(repeating: false, count: nodes.count)
        looseMass = nodes.map(\.inverseMass)
        start = nodes.map(\.position)
        vertexScratch = Array(repeating: Vertex(position: .zero, normal: .zero, uv: .zero), count: nodes.count)
        updateNormals()
    }

    func beginRoll() {
        rollGravity = 580 / pointsPerMeter
        rollAt = 0; rollSpeed = 0
        windRoll(previousToo: true)
    }

    private func windRoll(previousToo: Bool) {
        guard let at = rollAt else { return }
        let left = max(maxRestY - at, 0)
        let r0 = 8 / pointsPerMeter, k: Float = 0.012
        let outer = r0 + k * left
        for idx in columns..<nodes.count {
            let along = rest[idx].y
            if along <= at {
                if held[idx] { held[idx] = false; nodes[idx].inverseMass = looseMass[idx] }
                continue
            }
            held[idx] = true; nodes[idx].inverseMass = 0
            let sArc = along - at, r = r0 + k * (left - sArc)
            let turn = log(outer / max(r, 1e-5)) / k
            let p = V(start[idx].x, at + r * sin(turn), outer - r * cos(turn))
            nodes[idx].previous = previousToo ? p : nodes[idx].position
            nodes[idx].position = p
        }
    }

    static func breezeGain(at time: Float) -> Float {
        func swell(_ phase: Float, _ period: Float, _ duration: Float) -> Float {
            let age = phase.truncatingRemainder(dividingBy: period)
            return age < duration ? pow(sin(.pi * age / duration), 2) : 0
        }
        let breath = swell(time + 2.5, 11.5, 6.5)
        let passingGust = swell(time + 13.0, 26.0, 7.5)
        return min(1.32, 0.62 + 0.08 * sin(time * 0.42) + 0.32 * breath + 0.40 * passingGust)
    }

    static func clothPoint(screen p: CGPoint, frame: CGRect, width: Float) -> SIMD2<Float> {
        SIMD2(Float(p.x - frame.midX), Float(frame.maxY - p.y)) / width
    }

    func brush(from a: SIMD2<Float>, to b: SIMD2<Float>, over seconds: Double) {
        let aMeters = a * metersPerWidth, bMeters = b * metersPerWidth
        let segment = bMeters - aMeters
        let distance = simd_length(segment)
        guard distance > 0.003, seconds > 0, seconds < 0.15 else { brush = nil; return }
        let velocity = segment * (min(distance / Float(seconds), 11.0) / distance)
        brush = Brush(a: aMeters, segment: segment, velocity: velocity, lengthSquared: distance * distance, remaining: Float(seconds))
    }

    func projected(_ index: Int) -> SIMD2<Float> {
        let p = nodes[index].position
        return SIMD2(p.x + 0.14 * p.z, p.y - 0.04 * p.z) / metersPerWidth
    }

    func nearestPoint(to p: SIMD2<Float>) -> Int? {
        let radius = max(9 / widthPoints, 0.8 / Float(columns - 1))
        var bestDistance = radius * radius
        var best: Int?
        for index in columns..<nodes.count where !held[index] && (visibleNodes?.contains(index) ?? true) {
            let distance = simd_distance_squared(p, projected(index))
            if distance <= bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    func grab(at p: SIMD2<Float>) {
        releaseGrab()
        guard let index = nearestPoint(to: p) else { return }
        grabbed = index
        nodes[index].inverseMass = 0
        drag(to: p)
    }

    func drag(to p: SIMD2<Float>) {
        guard let index = grabbed else { return }
        let z = nodes[index].position.z
        let point = p * metersPerWidth
        let target = V(point.x - 0.14 * z, point.y + 0.04 * z, z)
        nodes[index].position = target
        nodes[index].previous = target
    }

    func releaseGrab() {
        guard let index = grabbed else { return }
        nodes[index].inverseMass = looseMass[index]
        grabbed = nil
    }

    func cut(from start: SIMD2<Float>, to end: SIMD2<Float>) {
        let stroke = end - start
        guard simd_length_squared(stroke) > 1e-12 else { return }
        let points = nodes.indices.map(projected)
        func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
        func crosses(_ i: Int, _ j: Int) -> Bool {
            let edge = points[j] - points[i]
            let denominator = cross(stroke, edge)
            guard abs(denominator) > 1e-10 else { return false }
            let delta = points[i] - start
            let t = cross(delta, edge) / denominator
            let u = cross(delta, stroke) / denominator
            return t >= 0 && t <= 1 && u >= 0 && u <= 1
        }
        joints.removeAll { crosses($0.a, $0.b) }
        let before = triangles.count
        triangles.removeAll { a, b, c in crosses(a,b) || crosses(b,c) || crosses(c,a) }
        if triangles.count != before {
            indices = triangles.flatMap { [UInt16($0.0), UInt16($0.1), UInt16($0.2)] }
            visibleNodes = Set(indices.map(Int.init))
            topologyVersion += 1
        }
        for index in columns..<nodes.count where crosses(index % columns, index) {
            cutTethers.insert(index)
        }
    }

    func gust() { gustStart = time }

    func advance(seconds: Double) {
        let t0 = CACurrentMediaTime()
        remainder += min(max(seconds, 0), 0.08)
        let stepSize = Double(Self.outerDt)
        var ran = false
        while remainder + 1e-9 >= stepSize {
            step()
            remainder -= stepSize
            ran = true
        }
        if ran { lastStepMs = (CACurrentMediaTime() - t0) * 1000.0 }
    }

    func step() {
        let subDt = dt, subDt2 = subDt * subDt, invSubDt = 1 / subDt
        let velDamp = exp(-damping * subDt)
        time += Self.outerDt
        let gain = wind <= 0.001 ? 0 : Self.breezeGain(at: time) * (wind <= 1.0 ? wind : (1.0 + (wind - 1.0) * 0.58))
        liveWindGain = gain

        let windArea: Float = config.model == .tension ? 0.24 : 1
        let tNow = time, gStart = gustStart, halfW = metersPerWidth * 0.5
        force.withUnsafeMutableBufferPointer { fBuf in
            for k in 0..<fBuf.count { fBuf[k] = .zero }
            nodes.withUnsafeBufferPointer { nBuf in
                triangles.withUnsafeBufferPointer { tBuf in
                    for idx in 0..<tBuf.count {
                        let (a, b, c) = tBuf[idx]
                        let pa = nBuf[a].position, pb = nBuf[b].position, pc = nBuf[c].position
                        let areaVector = simd_cross(pb - pa, pc - pa) * 0.5
                        let area = max(1e-8, simd_length(areaVector))
                        let n = areaVector / area
                        let center = (pa + pb + pc) * (1.0 / 3.0)
                        let velocity = (pa + pb + pc - nBuf[a].previous - nBuf[b].previous - nBuf[c].previous) * (invSubDt / 3.0)
                        let swell1 = sin(1.15 * tNow - 0.85 * center.x - 0.55 * center.y)
                        let swell2 = sin(1.65 * tNow + 1.25 * center.x - 1.10 * center.y + 1.4)
                        let eddy   = sin(2.15 * tNow - 2.10 * center.x - 1.60 * center.y + 0.7)
                        let gustAge = tNow - gStart - (center.x + halfW) * 0.14 - center.y * 0.20
                        let pulse: Float = gustAge > 0 && gustAge < 1.8 ? pow(sin(.pi * gustAge / 1.8), 2) : 0
                        let air = gain * V(1.65 + 2.15 * swell1 + 0.95 * eddy,
                                           -0.30 + 0.45 * swell2,
                                           1.10 + 3.05 * swell1 + 1.55 * swell2 + 0.60 * eddy)
                                + pulse * V(6.5, -1.2, 6.8)
                        let rel = air - velocity
                        let vn = simd_dot(rel, n)
                        let pressure = n * (vn * abs(vn) * 0.90) + (rel - n * vn) * min(simd_length(rel) * 0.11, 2.2)
                        let load = pressure * (area * windArea / 3.0)
                        fBuf[a] += load; fBuf[b] += load; fBuf[c] += load
                    }
                }
            }
        }

        let cols = columns, nodeCount = nodes.count, jointCount = joints.count, iters = iterations
        for _ in 0..<substeps {
            let activeBrush = brush
            nodes.withUnsafeMutableBufferPointer { nBuf in
                force.withUnsafeBufferPointer { fBuf in
                    held.withUnsafeBufferPointer { hBuf in
                        for k in cols..<nodeCount {
                            if hBuf[k] || grabbed == k { continue }
                            let pos = nBuf[k].position, prev = nBuf[k].previous
                            var accel = fBuf[k] * nBuf[k].inverseMass + V(0, 9.81, 0)
                            if let activeBrush {
                                let p = SIMD2(pos.x + 0.14 * pos.z, pos.y - 0.04 * pos.z)
                                let u = simd_clamp(simd_dot(p - activeBrush.a, activeBrush.segment) / activeBrush.lengthSquared, 0, 1)
                                let d = simd_distance(p, activeBrush.a + activeBrush.segment * u)
                                let influence = max(0, 1 - d / 0.45)
                                let v = activeBrush.velocity
                                accel += V(v.x, v.y, simd_length(v) * 0.55) * (influence * influence * 14)
                            }
                            let magSq = simd_length_squared(accel)
                            if magSq > 8100 { accel *= 90 / sqrt(magSq) }
                            nBuf[k].position = pos + (pos - prev) * velDamp + accel * subDt2
                            nBuf[k].previous = pos
                        }
                    }
                }
            }
            if var at = rollAt {
                rollSpeed += rollGravity * subDt
                at += rollSpeed * subDt
                if at >= maxRestY + 0.001 {
                    rollAt = nil
                    for k in cols..<nodeCount where held[k] { held[k] = false; nodes[k].inverseMass = looseMass[k] }
                } else { rollAt = at; windRoll(previousToo: false) }
            }
            if brush != nil {
                brush!.remaining -= subDt
                if brush!.remaining <= 0 { brush = nil }
            }
            nodes.withUnsafeMutableBufferPointer { nBuf in
                joints.withUnsafeMutableBufferPointer { jBuf in
                    for k in 0..<jointCount { jBuf[k].lambda = 0 }
                    for iter in 0..<iters {
                        let reverse = (iter & 1) == 1
                        for i in 0..<jointCount {
                            let k = reverse ? (jointCount - 1 - i) : i
                            let a = jBuf[k].a, b = jBuf[k].b
                            let wa = nBuf[a].inverseMass, wb = nBuf[b].inverseMass
                            let wSum = wa + wb
                            if wSum == 0 { continue }
                            let d = nBuf[b].position - nBuf[a].position
                            let distSq = simd_length_squared(d)
                            if distSq < 1e-16 { continue }
                            let distance = sqrt(distSq)
                            let alpha = jBuf[k].alpha
                            var dl = (-(distance - jBuf[k].length) - alpha * jBuf[k].lambda) / (wSum + alpha)
                            // A cord may pull its endpoints together but cannot push them apart.
                            if jBuf[k].tensionOnly { dl = min(dl, -jBuf[k].lambda) }
                            jBuf[k].lambda += dl
                            let correction = d * (dl / distance)
                            nBuf[a].position -= correction * wa
                            nBuf[b].position += correction * wb
                        }
                    }
                }
                rest.withUnsafeBufferPointer { rBuf in
                    held.withUnsafeBufferPointer { hBuf in
                        for k in cols..<nodeCount {
                            if hBuf[k] || grabbed == k || cutTethers.contains(k) { continue }
                            let anchor = nBuf[k % cols].position
                            let d = nBuf[k].position - anchor
                            let maxLen = rBuf[k].y * 1.006 + 0.008
                            let distSq = simd_length_squared(d)
                            if distSq > maxLen * maxLen {
                                nBuf[k].position = anchor + d * (maxLen / sqrt(distSq))
                            }
                        }
                    }
                }
            }
        }
    }

    func updateNormals() {
        let count = nodes.count
        nodes.withUnsafeMutableBufferPointer { nBuf in
            for i in 0..<count { nBuf[i].normal = .zero }
            triangles.withUnsafeBufferPointer { tBuf in
                for idx in 0..<tBuf.count {
                    let (a, b, c) = tBuf[idx]
                    let n = simd_cross(nBuf[b].position - nBuf[a].position, nBuf[c].position - nBuf[a].position)
                    nBuf[a].normal += n; nBuf[b].normal += n; nBuf[c].normal += n
                }
            }
        }
    }

    func vertices() -> [Vertex] {
        updateNormals()
        let invScale = 1 / metersPerWidth
        let count = nodes.count
        nodes.withUnsafeBufferPointer { nBuf in
            vertexScratch.withUnsafeMutableBufferPointer { vBuf in
                for i in 0..<count {
                    let node = nBuf[i]
                    let nLen = max(1e-8, simd_length(node.normal))
                    vBuf[i] = Vertex(position: SIMD4(node.position * invScale, 1),
                                     normal: SIMD4(node.normal / nLen, 0),
                                     uv: node.uv)
                }
            }
        }
        return vertexScratch
    }
}

// MARK: - 8K Texture Atlas & 4K Live Info Board

enum BannerMath {
    private static var cached: [URL: MTLTexture] = [:]
    private static var emptyCache: [UInt64: MTLTexture] = [:]

    static func emptyTexture(on gpu: MTLDevice) -> MTLTexture? {
        if let t = emptyCache[gpu.registryID] { return t }
        let spec = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        spec.usage = .shaderRead
        guard let t = gpu.makeTexture(descriptor: spec) else { return nil }
        var px: [UInt8] = [0, 0, 0, 0]
        t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 4)
        emptyCache[gpu.registryID] = t
        return t
    }

    static func texture(on gpu: MTLDevice, at url: URL) -> MTLTexture? {
        if let texture = cached[url], texture.device.registryID == gpu.registryID { return texture }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        guard w > 0, h > 0, w <= 16384, h <= 16384 else { return nil }
        var grayAlpha = [UInt8](repeating: 0, count: w * h * 2)
        let decoded = grayAlpha.withUnsafeMutableBytes { pixels -> Bool in
            guard let context = CGContext(data: pixels.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 2,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard decoded else { return nil }
        var alpha = [UInt8](repeating: 0, count: w * h)
        for i in alpha.indices { alpha[i] = grayAlpha[2 * i + 1] }
        let spec = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: h, mipmapped: true)
        spec.usage = .shaderRead
        guard let atlas = gpu.makeTexture(descriptor: spec), let queue = gpu.makeCommandQueue(),
              let buffer = queue.makeCommandBuffer(), let blit = buffer.makeBlitCommandEncoder() else { return nil }
        atlas.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: alpha, bytesPerRow: w)
        blit.generateMipmaps(for: atlas)
        blit.endEncoding(); buffer.commit(); buffer.waitUntilCompleted()
        guard buffer.status == .completed else { return nil }
        cached[url] = atlas
        return atlas
    }
}

enum BannerBoard {
    struct Section: Codable { let heading: String; let items: [String] }
    struct Payload: Codable {
        let eyebrow: String
        let title: String
        let subtitle: String?
        let sections: [Section]
        let footer: String?
    }
    static var customBoardURL: URL = AppPaths.boardURL
    static var inlineText: String?

    static func defaultPayload() -> Payload {
        let df = DateFormatter(); df.dateFormat = "EEEE, d MMM · HH:mm"
        let stamp = df.string(from: Date())
        let bat = batteryInfo().map { "Battery \($0.0)%\($0.1 ? " ⚡" : "")" } ?? "AC Power"
        let host = ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "")
        let cores = ProcessInfo.processInfo.processorCount
        let memGB = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        return Payload(
            eyebrow: "NOTCH BANNER · LIVE 4K BOARD",
            title: "Daily Briefing & System Status",
            subtitle: nil,
            sections: [
                Section(heading: "TODAY'S FOCUS", items: [
                    "Ship v1.0 release with 8K textures & 4× MSAA velvet",
                    "Review open pull requests before standup",
                    "Benchmark Ultra preset at 120 Hz ProMotion"
                ]),
                Section(heading: "AGENT & CI DIGEST", items: [
                    "Build pipeline: 14 / 14 checks green on main",
                    "Nightly cloth regression tests passed (0.0 ms drift)",
                    "3 tasks waiting for review in queue"
                ]),
                Section(heading: "WORKSTATION", items: [
                    "Host: \(host) · \(cores) cores · \(memGB) GB RAM",
                    "Power: \(bat)",
                    "Plugin API: write ~/.config/notch-banner/board.json"
                ])
            ],
            footer: "\(stamp)   ·   \(bat)   ·   NotchBanner 4K Metal"
        )
    }

    static func loadPayload() -> Payload {
        if let text = inlineText, !text.isEmpty {
            let lines = text.split(separator: "\n").map(String.init)
            return Payload(eyebrow: "NOTCH BANNER · LIVE NOTE",
                           title: lines.first ?? text,
                           subtitle: nil,
                           sections: [Section(heading: "MESSAGE", items: Array(lines.dropFirst()))],
                           footer: "NotchBanner CLI")
        }
        if let d = try? Data(contentsOf: customBoardURL), let p = try? JSONDecoder().decode(Payload.self, from: d), !p.sections.isEmpty {
            return p
        }
        return defaultPayload()
    }

    static func renderTexture(on gpu: MTLDevice, widthPoints: Float, heightPoints: Float, payload overridePayload: Payload? = nil) -> MTLTexture? {
        let payload = overridePayload ?? loadPayload()
        let borderScale = min(2.8, max(1.0, Double(widthPoints) / 330.0))
        let usableW = max(120.0, Double(widthPoints) * (1.0 - 2.0 * (0.078 / borderScale)))
        let usableH = max(90.0, Double(heightPoints) - 42.0 - Double(widthPoints) * (0.068 / borderScale))
        let ratio = max(0.16, min(3.2, usableH / usableW))
        let texW = widthPoints > 700 ? 3840 : 2400
        let texH = max(640, min(4096, Int((Double(texW) * ratio).rounded())))
        let bytesPerRow = texW * 4
        var pixels = [UInt8](repeating: 0, count: texH * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: texW, height: texH, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.translateBy(x: 0, y: CGFloat(texH))
            ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            defer { NSGraphicsContext.restoreGraphicsState() }

            let W = CGFloat(texW), H = CGFloat(texH)
            let padX = W * 0.045, padY = H * 0.075
            let contentW = W - 2 * padX
            let s = min(W / 2400.0, H / 760.0) * 1.05
            let gold = NSColor(calibratedRed: 0.94, green: 0.80, blue: 0.50, alpha: 0.96)
            let ivory = NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.91, alpha: 0.97)
            let muted = NSColor(calibratedRed: 0.84, green: 0.81, blue: 0.75, alpha: 0.80)
            let ruleColor = NSColor(calibratedRed: 0.90, green: 0.76, blue: 0.46, alpha: 0.36)

            let cardPath = NSBezierPath(roundedRect: NSRect(x: padX * 0.55, y: padY * 0.45, width: W - padX * 1.1, height: H - padY * 0.9), xRadius: 24 * s, yRadius: 24 * s)
            NSColor(calibratedWhite: 0.02, alpha: 0.38).setFill(); cardPath.fill()
            NSColor(calibratedRed: 0.90, green: 0.76, blue: 0.46, alpha: 0.30).setStroke()
            cardPath.lineWidth = max(2, 2.5 * s); cardPath.stroke()

            var y = padY
            let eyebrowFont = NSFont.monospacedSystemFont(ofSize: max(20, 24 * s), weight: .semibold)
            (payload.eyebrow as NSString).draw(in: NSRect(x: padX, y: y, width: contentW, height: 34 * s),
                                               withAttributes: [.font: eyebrowFont, .foregroundColor: gold, .kern: 3.5 * s])
            y += 32 * s

            let titleFont = NSFont(name: "Georgia-Bold", size: max(36, 48 * s)) ?? NSFont.systemFont(ofSize: max(36, 48 * s), weight: .bold)
            let titlePara = NSMutableParagraphStyle(); titlePara.lineBreakMode = .byTruncatingTail
            (payload.title as NSString).draw(in: NSRect(x: padX, y: y, width: contentW, height: 64 * s),
                                             withAttributes: [.font: titleFont, .foregroundColor: ivory, .paragraphStyle: titlePara])
            y += 64 * s

            ruleColor.setFill()
            NSRect(x: padX, y: y, width: contentW, height: max(2, 2.5 * s)).fill()
            y += 22 * s

            let footerH: CGFloat = 42 * s
            let bodyH = max(100, H - padY - footerH - y)
            let cols = (W / H > 1.75) ? min(payload.sections.count, 3) : 1
            let colGap = 44 * s
            let colW = (contentW - colGap * CGFloat(max(0, cols - 1))) / CGFloat(max(1, cols))
            let headFont = NSFont.monospacedSystemFont(ofSize: max(18, 22 * s), weight: .bold)
            let itemFont = NSFont.systemFont(ofSize: max(22, 28 * s), weight: .medium)
            let itemPara = NSMutableParagraphStyle(); itemPara.lineBreakMode = .byWordWrapping; itemPara.lineSpacing = 5 * s

            for idx in 0..<min(payload.sections.count, cols == 1 ? 2 : 3) {
                let sec = payload.sections[idx]
                let cx = padX + CGFloat(idx % cols) * (colW + colGap)
                var cy = cols == 1 ? (y + CGFloat(idx) * (bodyH * 0.5)) : y
                let colBottom = cols == 1 ? (cy + bodyH * 0.48) : (y + bodyH)
                (sec.heading as NSString).draw(in: NSRect(x: cx, y: cy, width: colW, height: 30 * s),
                                               withAttributes: [.font: headFont, .foregroundColor: gold, .kern: 2.2 * s])
                cy += 34 * s
                for item in sec.items {
                    guard cy + 32 * s < colBottom else { break }
                    let bullet = "•  " + item
                    let rect = NSRect(x: cx, y: cy, width: colW, height: min(105 * s, colBottom - cy))
                    let attr: [NSAttributedString.Key: Any] = [.font: itemFont, .foregroundColor: ivory, .paragraphStyle: itemPara]
                    let measured = (bullet as NSString).boundingRect(with: NSSize(width: colW, height: rect.height), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attr)
                    (bullet as NSString).draw(in: rect, withAttributes: attr)
                    cy += min(measured.height, rect.height) + 12 * s
                }
            }

            if let footer = payload.footer, !footer.isEmpty {
                let fy = H - padY * 0.85 - 28 * s
                ruleColor.setFill()
                NSRect(x: padX, y: fy - 10 * s, width: contentW, height: max(1.5, 2 * s)).fill()
                let fFont = NSFont.monospacedSystemFont(ofSize: max(18, 21 * s), weight: .regular)
                (footer as NSString).draw(in: NSRect(x: padX, y: fy, width: contentW, height: 32 * s),
                                          withAttributes: [.font: fFont, .foregroundColor: muted])
            }
            return true
        }
        guard ok else { return nil }
        let spec = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: texW, height: texH, mipmapped: true)
        spec.usage = .shaderRead
        guard let tex = gpu.makeTexture(descriptor: spec), let q = gpu.makeCommandQueue(),
              let cb = q.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, texW, texH), mipmapLevel: 0, withBytes: pixels, bytesPerRow: bytesPerRow)
        blit.generateMipmaps(for: tex)
        blit.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        return cb.status == .completed ? tex : nil
    }
}

// MARK: - Metal Renderer

final class ClothRenderer {
    let gpu: MTLDevice
    let pipeline: MTLRenderPipelineState
    let sampleCount: Int
    var dye = BannerDye.garnet
    var strandSpacing: StrandSpacing = .fine
    var collarDepth: Float = 0.03
    var bodyOpacity: Float = 1
    var collarOpacity: Float = 1
    var print: BannerPrint = .robe { didSet { if oldValue != print { loadPrint() } } }
    private(set) var mathematics: MTLTexture?
    private(set) var boardTexture: MTLTexture?
    private let fallbackTexture: MTLTexture?
    private var lastBoardRefresh = Date.distantPast
    let depthState: MTLDepthStencilState
    private var indexBuffer: MTLBuffer?
    private var uploadedTopology = -1
    private let vertexBuffers: [MTLBuffer]
    private var vertexRing = 0
    let cloth: BannerCloth

    func refreshBoardIfNeeded(force: Bool = false, payload: BannerBoard.Payload? = nil) {
        guard print == .board else { return }
        if !force, boardTexture != nil, Date().timeIntervalSince(lastBoardRefresh) < 45 { return }
        lastBoardRefresh = Date()
        boardTexture = BannerBoard.renderTexture(on: gpu, widthPoints: cloth.widthPoints, heightPoints: cloth.widthPoints * cloth.aspect, payload: payload)
    }

    private func loadPrint() {
        if print == .board { mathematics = nil; refreshBoardIfNeeded(force: true); return }
        guard let name = print.textureFile else { mathematics = nil; return }
        let url = AppPaths.resource(name)
        mathematics = BannerMath.texture(on: gpu, at: url)
    }

    init(gpu: MTLDevice, library: MTLLibrary, aspect: Float, widthPoints: Float,
         cutout: BannerCutout = .none, config: BannerPhysics = BannerPhysics(), sampleCount: Int = 4) throws {
        self.gpu = gpu
        self.sampleCount = sampleCount
        self.cloth = BannerCloth(aspect: aspect, widthPoints: widthPoints, cutout: cutout, config: config)
        self.fallbackTexture = BannerMath.emptyTexture(on: gpu)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "clothVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "clothVelvet")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.rasterSampleCount = sampleCount
        pipeline = try gpu.makeRenderPipelineState(descriptor: descriptor)
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less; depth.isDepthWriteEnabled = true
        depthState = gpu.makeDepthStencilState(descriptor: depth)!
        let vBytes = cloth.nodes.count * MemoryLayout<BannerCloth.Vertex>.stride
        vertexBuffers = (0..<3).compactMap { _ in gpu.makeBuffer(length: vBytes, options: .storageModeShared) }
        loadPrint()
    }

    func draw(_ encoder: MTLRenderCommandEncoder, viewport: SIMD2<Float>) {
        guard !vertexBuffers.isEmpty else { return }
        refreshBoardIfNeeded()
        let vertices = cloth.vertices()
        let buffer = vertexBuffers[vertexRing]
        vertexRing = (vertexRing + 1) % vertexBuffers.count
        vertices.withUnsafeBytes { raw in
            if let src = raw.baseAddress { memcpy(buffer.contents(), src, raw.count) }
        }
        var scene = SIMD4<Float>(viewport.x, viewport.y, cloth.aspect, Float(dye.rawValue))
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&scene, length: MemoryLayout.size(ofValue: scene), index: 1)
        encoder.setFragmentBytes(&scene, length: MemoryLayout.size(ofValue: scene), index: 0)
        encoder.setFragmentTexture(mathematics ?? fallbackTexture, index: 0)
        encoder.setFragmentTexture(boardTexture ?? fallbackTexture, index: 1)
        let style: BannerPrint
        if print == .board { style = boardTexture != nil ? .board : .robe }
        else if mathematics == nil && print.textureFile != nil { style = .robe }
        else { style = print }
        var fabric = SIMD4<Float>(collarDepth, bodyOpacity, Float(style.rawValue), cloth.tail)
        var extra = SIMD4<Float>(cloth.widthPoints / 330.0, Float(cloth.cutout.shaderId), collarOpacity, 1.0)
        encoder.setFragmentBytes(&fabric, length: MemoryLayout.size(ofValue: fabric), index: 1)
        encoder.setFragmentBytes(&extra, length: MemoryLayout.size(ofValue: extra), index: 2)
        var grid = cloth.widthPoints / strandSpacing.points
        encoder.setFragmentBytes(&grid, length: MemoryLayout.size(ofValue: grid), index: 3)
        if uploadedTopology != cloth.topologyVersion {
            indexBuffer = cloth.indices.isEmpty ? nil : gpu.makeBuffer(bytes: cloth.indices, length: cloth.indices.count * MemoryLayout<UInt16>.stride)
            uploadedTopology = cloth.topologyVersion
        }
        guard let indices = indexBuffer else { return }
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: cloth.indices.count, indexType: .uint16, indexBuffer: indices, indexBufferOffset: 0)
    }
}

// MARK: - Live Diagnostics HUD & Settings Panel

final class BannerStats: ObservableObject {
    static let shared = BannerStats()
    @Published var fps: Double = 0
    @Published var fpsHistory: [Double] = []
    @Published var frameMs: Double = 0
    @Published var physicsMs: Double = 0
    @Published var drawMs: Double = 0
    @Published var columns: Int = 0
    @Published var rows: Int = 0
    @Published var nodes: Int = 0
    @Published var triangles: Int = 0
    @Published var joints: Int = 0
    @Published var drawableW: Int = 0
    @Published var drawableH: Int = 0
    @Published var msaa: Int = 4
    @Published var atlasPx: Int = 0
    @Published var widthMeters: Float = 0
    @Published var heightMeters: Float = 0
    @Published var mass: Float = 0.85
    @Published var liveWind: Float = 0
    @Published var quality: String = "High"
    @Published var cutout: String = "Straight"
    @Published var style: String = ""
    @Published var active: Bool = false

    func record(fps: Double, frameMs: Double, physicsMs: Double, drawMs: Double, cloth: BannerCloth,
                drawableW: Int, drawableH: Int, msaa: Int, atlasPx: Int, style: String) {
        self.fps = fps; self.frameMs = frameMs; self.physicsMs = physicsMs; self.drawMs = drawMs
        self.columns = cloth.columns; self.rows = cloth.rows; self.nodes = cloth.nodes.count
        self.triangles = cloth.triangleCount; self.joints = cloth.joints.count
        self.drawableW = drawableW; self.drawableH = drawableH; self.msaa = msaa; self.atlasPx = atlasPx
        self.widthMeters = cloth.metersPerWidth; self.heightMeters = cloth.heightMeters
        self.mass = cloth.config.mass; self.liveWind = cloth.liveWindGain
        self.quality = cloth.config.quality.title; self.cutout = cloth.cutout.title
        self.style = style; self.active = true
        self.fpsHistory.append(fps)
        if self.fpsHistory.count > 60 { self.fpsHistory.removeFirst() }
    }
}

struct BannerStatsHUDView: View {
    @ObservedObject var s = BannerStats.shared
    var onClose: () -> Void
    var fpsColor: Color {
        if s.fps >= 55 { return Color(red: 0.45, green: 0.92, blue: 0.58) }
        if s.fps >= 28 { return Color(red: 0.98, green: 0.82, blue: 0.40) }
        return Color(red: 0.98, green: 0.42, blue: 0.42)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NOTCH BANNER · DIAGNOSTICS").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.65))
                Spacer()
                Text(s.quality.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Color.white.opacity(0.12)).cornerRadius(4).foregroundColor(.white)
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.6)) }.buttonStyle(.plain)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(s.active ? String(format: "%.0f", s.fps) : "—").font(.system(size: 32, weight: .bold, design: .monospaced)).foregroundColor(fpsColor)
                Text("FPS").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "Frame %.1f ms", s.frameMs)).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                    Text(String(format: "Sim %.2f ms · GPU %.2f ms", s.physicsMs, s.drawMs)).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                }
            }
            GeometryReader { geo in
                let pts = s.fpsHistory
                let maxV = max(65.0, (pts.max() ?? 60) * 1.1)
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))
                    if pts.count > 1 {
                        Path { p in
                            for (i, v) in pts.enumerated() {
                                let x = geo.size.width * CGFloat(i) / CGFloat(max(1, pts.count - 1))
                                let y = geo.size.height * (1 - CGFloat(min(v, maxV) / maxV))
                                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }.stroke(fpsColor, lineWidth: 1.5)
                    }
                }
            }.frame(height: 32)
            Divider().background(Color.white.opacity(0.14))
            row("Mesh", "\(s.columns) × \(s.rows)  (\(s.nodes) nodes · \(s.triangles) tris)")
            row("XPBD", "\(s.joints) constraints")
            row("Drawable", "\(s.drawableW) × \(s.drawableH) px · \(s.msaa)× MSAA")
            row("Atlas", s.atlasPx > 0 ? "\(s.atlasPx) px texture" : "Procedural 4K+")
            row("Curtain", String(format: "%.1fm × %.1fm · %.2f kg/m² · wind %.2f", s.widthMeters, s.heightMeters, s.mass, s.liveWind))
            row("Style", "\(s.style) · \(s.cutout)")
        }
        .padding(12).frame(width: 318)
        .background(Color(red: 0.06, green: 0.07, blue: 0.09).opacity(0.93)).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.16), lineWidth: 1))
    }
    func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.55)).frame(width: 62, alignment: .leading)
            Text(v).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.92)).lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

final class SettingsStore: ObservableObject {
    @Published var settings: BannerConfig
    @Published var isVisible: Bool
    @Published var currentPrint: BannerPrint
    @Published var currentDye: BannerDye
    @Published var currentCutout: BannerCutout
    @Published var widthFraction: Double
    @Published var heightFraction: Double
    @Published var screenWidth: CGFloat
    @Published var screenHeight: CGFloat
    @Published var notchWidth: CGFloat
    @Published var notchHeight: CGFloat
    @Published var tab: Int = 0

    init(settings: BannerConfig, isVisible: Bool, print: BannerPrint, dye: BannerDye, cutout: BannerCutout,
         widthFraction: Double, heightFraction: Double, screen: CGSize, notch: CGSize) {
        self.settings = settings; self.isVisible = isVisible
        self.currentPrint = print; self.currentDye = dye; self.currentCutout = cutout
        self.widthFraction = widthFraction; self.heightFraction = heightFraction
        self.screenWidth = screen.width; self.screenHeight = screen.height
        self.notchWidth = notch.width; self.notchHeight = notch.height
    }
}

struct BannerSettingsView: View {
    @ObservedObject var m: SettingsStore
    var onSave: (BannerConfig, Bool) -> Void
    var onSetNow: (BannerPrint?, BannerDye?, BannerCutout?, Double?, Double?, Double?) -> Void
    var onToggleVisible: () -> Void
    var onNext: () -> Void
    var onGust: () -> Void
    var onToggleStats: () -> Void
    var onShowBoard: () -> Void
    var onClose: () -> Void
    var onMend: () -> Void

    let dyeSwatches: [BannerDye: Color] = [
        .black: Color(red: 0.14, green: 0.14, blue: 0.16),
        .garnet: Color(red: 0.48, green: 0.11, blue: 0.17),
        .pine: Color(red: 0.09, green: 0.30, blue: 0.19),
        .midnight: Color(red: 0.11, green: 0.17, blue: 0.38)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("BANNER STUDIO").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(Color(red: 0.92, green: 0.78, blue: 0.48))
                Spacer()
                Button(m.isVisible ? "Hide" : "Show") { onToggleVisible(); m.isVisible.toggle() }.controlSize(.small)
                Button("Next", action: onNext).controlSize(.small)
                Button("Gust", action: onGust).controlSize(.small)
                Button("Board", action: onShowBoard).controlSize(.small)
                Button("FPS", action: onToggleStats).controlSize(.small)
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundColor(.white.opacity(0.6)) }.buttonStyle(.plain)
            }
            HStack(spacing: 4) {
                ForEach([(0, "Now (Live)"), (1, "Physics & Quality"), (2, "Random Rotation")], id: \.0) { idx, title in
                    let on = m.tab == idx
                    Button(title) { m.tab = idx }
                        .font(.system(size: 11, weight: on ? .bold : .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(on ? Color(red: 0.72, green: 0.56, blue: 0.28) : Color.white.opacity(0.08))
                        .foregroundColor(.white).cornerRadius(6).buttonStyle(.plain)
                }
            }
            Divider().background(Color.white.opacity(0.14))
            ScrollView {
                if m.tab == 0 { nowTab } else if m.tab == 1 { physicsTab } else { rotationTab }
            }.frame(maxWidth: .infinity)
        }
        .padding(14).frame(width: 440)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10).opacity(0.96)).cornerRadius(13)
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    var nowTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("SURFACE")
                HStack {
                    ForEach([BannerPrint.mesh, .grid], id: \.rawValue) { p in
                        chip(p.title, active: m.currentPrint == p, accent: Color(red: 0.26, green: 0.44, blue: 0.62)) {
                            m.settings.pinnedWeave = p.key; m.currentPrint = p; m.isVisible = true
                            onSetNow(p, nil, nil, nil, nil, nil)
                        }
                    }
                }
                if m.currentPrint == .mesh || m.currentPrint == .grid {
                    sectionLabel("STRAND SPACING")
                    HStack {
                        ForEach(StrandSpacing.allCases, id: \.self) { spacing in
                            chip(String(format: "%g pt", spacing.points), active: m.settings.strandSpacing == spacing, accent: .teal) {
                                m.settings.strandSpacing = spacing; onSave(m.settings, false)
                            }
                        }
                    }
                }
                sectionLabel("FABRIC PRINTS")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                    ForEach(BannerPrint.allCases.filter { $0 != .mesh && $0 != .grid }, id: \.rawValue) { p in
                        let short = p.shortTitle
                        chip(short, active: m.currentPrint == p, accent: Color(red: 0.72, green: 0.56, blue: 0.28)) {
                            m.settings.pinnedWeave = nil; m.currentPrint = p; m.isVisible = true; onSetNow(p, nil, nil, nil, nil, nil)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                sliderRow("Position", value: $m.settings.offset, range: -1...1, fmt: "%+.0f%%", scaleDisplay: 100, rebuild: true)
                Toggle("Split the middle", isOn: Binding(get: { m.settings.split }, set: {
                    m.settings.split = $0; onSave(m.settings, true)
                })).toggleStyle(.checkbox)
                if m.currentPrint == .mesh {
                    HStack {
                        Text("Left-drag a knot. Right-drag to cut.").font(.caption)
                        Spacer()
                        Button("Mend net", action: onMend).controlSize(.small)
                    }.foregroundColor(.white.opacity(0.86))
                }
                sectionLabel("COLOUR")
                HStack(spacing: 4) {
                    ForEach(BannerDye.allCases, id: \.rawValue) { d in
                        let on = m.currentDye == d
                        Button(action: { m.currentDye = d; m.isVisible = true; onSetNow(nil, d, nil, nil, nil, nil) }) {
                            HStack(spacing: 4) {
                                Circle().fill(dyeSwatches[d] ?? .gray).frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.8))
                                Text(d.title).font(.system(size: 10, weight: on ? .bold : .regular))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(on ? Color.white.opacity(0.22) : Color.white.opacity(0.07))
                            .foregroundColor(.white).cornerRadius(5)
                        }.buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("BOTTOM CUTOUT RIGHT NOW")
                HStack(spacing: 4) {
                    ForEach(BannerCutout.allCases, id: \.rawValue) { c in
                        let lbl = c == .none ? "Straight" : (c.title.components(separatedBy: " ").first ?? c.title)
                        chip(lbl, active: m.currentCutout == c, accent: Color(red: 0.26, green: 0.44, blue: 0.62)) {
                            m.currentCutout = c; m.isVisible = true; onSetNow(nil, nil, c, nil, nil, nil)
                        }
                    }
                }
            }
            Divider().background(Color.white.opacity(0.12))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    sectionLabel("WIDTH (PRESETS OR FREE SLIDER)")
                    Spacer()
                    Text("\(Int((m.widthFraction * 100).rounded()))% · \(Int((m.widthFraction * Double(m.screenWidth)).rounded())) pt")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.75))
                }
                HStack(spacing: 4) {
                    ForEach(BannerWidth.allCases, id: \.rawValue) { w in
                        let f = w.fraction(notch: m.notchWidth, screen: m.screenWidth)
                        chip(w.shortTitle, active: abs(m.widthFraction - f) < 0.025, accent: Color(red: 0.26, green: 0.44, blue: 0.62)) {
                            m.widthFraction = f; m.settings.widthFraction = f; m.isVisible = true; onSetNow(nil, nil, nil, f, nil, nil)
                        }
                    }
                }
                Slider(value: Binding(get: { m.widthFraction }, set: { v in
                    m.widthFraction = v; m.settings.widthFraction = v; m.isVisible = true; onSetNow(nil, nil, nil, v, nil, nil)
                }), in: 0.14...1.0)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    sectionLabel("HEIGHT (PRESETS OR FREE SLIDER)")
                    Spacer()
                    Text("\(Int((m.heightFraction * 100).rounded()))% · \(Int((m.heightFraction * Double(m.screenHeight)).rounded())) pt")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.75))
                }
                HStack(spacing: 4) {
                    ForEach([BannerLength.ultraShort, .short, .half, .full], id: \.rawValue) { l in
                        let f = l.fraction(notch: m.notchHeight, available: m.screenHeight)
                        chip(l.shortTitle, active: abs(m.heightFraction - f) < 0.02, accent: Color(red: 0.26, green: 0.44, blue: 0.62)) {
                            m.heightFraction = f; m.settings.heightFraction = f; m.isVisible = true; onSetNow(nil, nil, nil, nil, f, nil)
                        }
                    }
                }
                Slider(value: Binding(get: { m.heightFraction }, set: { v in
                    m.heightFraction = v; m.settings.heightFraction = v; m.isVisible = true; onSetNow(nil, nil, nil, nil, v, nil)
                }), in: 0.06...1.0)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    sectionLabel("OPACITY")
                    Spacer()
                    ForEach([1.0, 0.72, 0.46], id: \.self) { o in
                        let on = abs(m.settings.opacity - o) < 0.03
                        Button("\(Int((o * 100).rounded()))%") { m.settings.opacity = o; onSetNow(nil, nil, nil, nil, nil, o) }
                            .font(.system(size: 9, weight: on ? .bold : .regular, design: .monospaced))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(on ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
                            .foregroundColor(.white).cornerRadius(4).buttonStyle(.plain)
                    }
                    Text("\(Int((m.settings.opacity * 100).rounded()))%").font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.85)).frame(width: 38, alignment: .trailing)
                }
                Slider(value: Binding(get: { m.settings.opacity }, set: { v in m.settings.opacity = v; onSetNow(nil, nil, nil, nil, nil, v) }), in: 0.10...1.0)
            }
            Divider().background(Color.white.opacity(0.12))
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Transparent on mouse hover", isOn: Binding(get: { m.settings.fadeOnHover }, set: {
                    m.settings.fadeOnHover = $0; onSave(m.settings, false)
                })).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.9))
                if m.settings.fadeOnHover {
                    sliderRow("Hover alpha", value: $m.settings.hoverOpacity, range: 0.0...0.85, fmt: "%.0f%%", scaleDisplay: 100, rebuild: false)
                    sliderRow("Top border", value: $m.settings.topHoverOpacity, range: 0.0...0.50, fmt: "%.0f%%", scaleDisplay: 100, rebuild: false)
                    sliderRow("Top zone", value: $m.settings.topHoverZone, range: 40...240, fmt: "%.0f pt", rebuild: false)
                }
            }
        }
    }

    var physicsTab: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("PHYSICS MODEL")
            HStack {
                ForEach(ClothModel.allCases, id: \.self) { model in
                    chip(model == .original ? "Original velvet" : "Tension net", active: m.settings.clothModel == model, accent: .teal) {
                        m.settings.clothModel = model; onSave(m.settings, true)
                    }
                }
            }
            sectionLabel("SIMULATED MESH RESOLUTION")
            HStack {
                ForEach(ClothResolution.allCases, id: \.self) { resolution in
                    chip(resolution.rawValue.capitalized, active: m.settings.clothResolution == resolution, accent: .teal) {
                        m.settings.clothResolution = resolution; onSave(m.settings, true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("QUALITY TIER")
                HStack(spacing: 4) {
                    ForEach(BannerQuality.allCases, id: \.rawValue) { q in
                        chip(q.title, active: m.settings.quality == q.rawValue, accent: Color(red: 0.72, green: 0.56, blue: 0.28)) {
                            m.settings.quality = q.rawValue; onSave(m.settings, true)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    sectionLabel("WIND STRENGTH")
                    Spacer()
                    ForEach([("Still", 0.0), ("Breeze", 1.0), ("Gale", 2.1)], id: \.0) { lbl, v in
                        Button(lbl) { m.settings.windStrength = v; onSave(m.settings, false) }
                            .font(.system(size: 9, weight: abs(m.settings.windStrength - v) < 0.05 ? .bold : .regular))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(abs(m.settings.windStrength - v) < 0.05 ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
                            .foregroundColor(.white).cornerRadius(4).buttonStyle(.plain)
                    }
                }
                sliderRow("Wind", value: $m.settings.windStrength, range: 0...3.0, fmt: "%.2f×", rebuild: false)
            }
            Divider().background(Color.white.opacity(0.12))
            sliderRow("Size (Scale)", value: $m.settings.scale, range: 0.4...2.5, fmt: "%.2f×", rebuild: true)
            sliderRow("Mass", value: $m.settings.mass, range: 0.20...2.2, fmt: "%.2f kg/m²", rebuild: true)
            sliderRow("Stiffness", value: $m.settings.stiffness, range: 0.25...2.5, fmt: "%.2f×", rebuild: true)
            sliderRow("Damping", value: $m.settings.damping, range: 0.15...2.0, fmt: "%.2f", rebuild: false)
            sliderRow("Pleats", value: $m.settings.pleats, range: 0.0...1.6, fmt: "%.2f×", rebuild: true)
            HStack {
                Spacer()
                Button("Reset Theater Velvet Defaults") {
                    m.settings.clothModel = .original; m.settings.clothResolution = .auto
                    m.settings.quality = BannerQuality.high.rawValue
                    m.settings.windStrength = 1.0; m.settings.scale = 1.0; m.settings.mass = 0.85
                    m.settings.stiffness = 1.0; m.settings.damping = 0.65; m.settings.pleats = 1.0
                    m.settings.opacity = 1.0; m.settings.fadeOnHover = true
                    m.settings.hoverOpacity = 0.22; m.settings.topHoverOpacity = 0.08; m.settings.topHoverZone = 115
                    onSave(m.settings, true)
                }.controlSize(.small)
            }
        }
    }

    var rotationTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    sectionLabel("AUTO-SWITCH INTERVAL")
                    Spacer()
                    Text(m.settings.minutes < 0.5 ? "Never" : "\(Int(m.settings.minutes.rounded())) min")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                }
                HStack(spacing: 4) {
                    ForEach(BannerConfig.everyChoices, id: \.0) { lbl, v in
                        chip(lbl, active: abs(m.settings.minutes - v) < 0.25, accent: Color(red: 0.72, green: 0.56, blue: 0.28)) {
                            m.settings.minutes = v; onSave(m.settings, false)
                        }
                    }
                }
                Slider(value: Binding(get: { m.settings.minutes }, set: { m.settings.minutes = $0.rounded(); onSave(m.settings, false) }), in: 0...120)
            }
            Divider().background(Color.white.opacity(0.12))
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("PATTERNS IN ROTATION")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                    ForEach(BannerPrint.allCases, id: \.rawValue) { p in
                        let short = p.shortTitle
                        chip(short, active: m.settings.patterns.contains(p.key), accent: Color(red: 0.26, green: 0.44, blue: 0.62)) {
                            togglePool(&m.settings.patterns, p.key); onSave(m.settings, false)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("COLOURS IN ROTATION")
                HStack(spacing: 4) {
                    ForEach(BannerDye.allCases, id: \.rawValue) { d in
                        chip(d.title, active: m.settings.colours.contains(d.key), accent: Color(red: 0.26, green: 0.44, blue: 0.62)) {
                            togglePool(&m.settings.colours, d.key); onSave(m.settings, false)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("WIDTHS IN ROTATION (CLEARS FREE WIDTH LOCK)")
                HStack(spacing: 4) {
                    ForEach(BannerWidth.allCases, id: \.rawValue) { w in
                        chip(w.shortTitle, active: m.settings.widths.contains(w.rawValue), accent: Color(red: 0.26, green: 0.44, blue: 0.62)) {
                            m.settings.widthFraction = nil; togglePool(&m.settings.widths, w.rawValue); onSave(m.settings, false)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("CUTOUTS IN ROTATION")
                HStack(spacing: 4) {
                    ForEach(BannerCutout.allCases, id: \.rawValue) { c in
                        let lbl = c == .none ? "Straight" : (c.title.components(separatedBy: " ").first ?? c.title)
                        chip(lbl, active: m.settings.cutouts.contains(c.rawValue), accent: Color(red: 0.26, green: 0.44, blue: 0.62)) {
                            togglePool(&m.settings.cutouts, c.rawValue); onSave(m.settings, true)
                        }
                    }
                }
            }
        }
    }

    func togglePool(_ arr: inout [String], _ key: String) {
        if let i = arr.firstIndex(of: key) { if arr.count > 1 { arr.remove(at: i) } } else { arr.append(key) }
    }
    func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.55))
    }
    func chip(_ label: String, active: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.system(size: 10, weight: active ? .bold : .regular))
            .frame(maxWidth: .infinity).padding(.horizontal, 6).padding(.vertical, 4)
            .background(active ? accent : Color.white.opacity(0.08))
            .foregroundColor(.white).cornerRadius(5).buttonStyle(.plain)
    }
    func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, fmt: String, scaleDisplay: Double = 1, rebuild: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.82)).frame(width: 82, alignment: .leading)
            Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; onSave(m.settings, rebuild) }), in: range)
            Text(String(format: fmt, value.wrappedValue * scaleDisplay)).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.85)).frame(width: 68, alignment: .trailing)
        }
    }
}

// MARK: - Live Interactive Window & Menu Bar App

final class BannerCanvas: MTKView, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let library: MTLLibrary
    private var renderer: ClothRenderer?
    private var lastFrame = CACurrentMediaTime()
    private var clothWidth: Float = 1
    private var clothHeight: Float = 1
    private var previousPointer: CGPoint?
    private var statsTimer: Double = 0
    private var smoothFps: Double = 60
    private var smoothFrameMs: Double = 16.6
    private var smoothBodyOpacity: Float = 1
    private var smoothCollarOpacity: Float = 1
    var dye = BannerDye.garnet { didSet { renderer?.dye = dye } }
    var print = BannerPrint.robe { didSet { renderer?.print = print } }
    var bodyOpacity: Float = 1
    var fadeOnHover: Bool = true
    var hoverOpacity: Float = 0.22
    var topHoverOpacity: Float = 0.08
    var topHoverZone: Float = 115
    var wind: Float = 1 { didSet { renderer?.cloth.wind = wind } }
    var damping: Float = 0.65 { didSet { renderer?.cloth.damping = damping } }
    func gust() { renderer?.cloth.gust() }
    func refreshBoard() { renderer?.refreshBoardIfNeeded(force: true) }

    var strandSpacing: StrandSpacing = .fine { didSet { renderer?.strandSpacing = strandSpacing } }
    private var lastCut: SIMD2<Float>?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func point(_ event: NSEvent) -> SIMD2<Float> {
        let local = convert(event.locationInWindow, from: nil)
        return SIMD2(Float(local.x - bounds.midX), Float(isFlipped ? local.y : bounds.maxY - local.y)) / clothWidth
    }
    override func mouseDown(with event: NSEvent) {
        renderer?.cloth.grab(at: point(event))
        if renderer?.cloth.grabbed != nil { setAccessibilityValue("Holding a mesh knot") }
    }
    override func mouseDragged(with event: NSEvent) { renderer?.cloth.drag(to: point(event)) }
    override func mouseUp(with event: NSEvent) {
        renderer?.cloth.releaseGrab()
        setAccessibilityValue("Released mesh knot")
    }
    override func rightMouseDown(with event: NSEvent) { lastCut = point(event) }
    override func rightMouseDragged(with event: NSEvent) {
        let next = point(event)
        if let lastCut { renderer?.cloth.cut(from: lastCut, to: next) }
        lastCut = next
    }
    override func rightMouseUp(with event: NSEvent) {
        rightMouseDragged(with: event)
        if let cloth = renderer?.cloth { setAccessibilityValue("Mesh revision \(cloth.topologyVersion), \(cloth.triangleCount) triangles") }
        lastCut = nil
    }

    init?(frame: NSRect, metal: MTLDevice) {
        guard let queue = metal.makeCommandQueue() else { return nil }
        guard let src = try? String(contentsOf: AppPaths.resource("banner.metal"), encoding: .utf8) else {
            NSLog("Cannot read banner.metal at %@", AppPaths.resource("banner.metal").path); return nil
        }
        do { library = try metal.makeLibrary(source: src, options: nil) }
        catch { NSLog("Banner shader error: %@", error.localizedDescription); return nil }
        self.queue = queue
        super.init(frame: frame, device: metal)
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel("Banner cloth")
        wantsLayer = true; layer?.isOpaque = false
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        depthStencilPixelFormat = .depth32Float
        sampleCount = 4
        preferredFramesPerSecond = 60
        autoResizeDrawable = false
        delegate = self
    }
    required init(coder: NSCoder) { fatalError("unavailable") }

    func unfold(to height: CGFloat, width: CGFloat, collar: CGFloat,
                cutout: BannerCutout, config: BannerPhysics, drop: Bool) {
        let native = window?.backingScaleFactor ?? 2
        let area = max(1, bounds.width * bounds.height)
        let maxScale: CGFloat = config.quality == .ultra ? 6 : 5
        let scale = max(native, min(maxScale, sqrt(config.quality.pixelBudget / area)))
        let wantedMsaa = (device?.supportsTextureSampleCount(config.quality.msaa) ?? false) ? config.quality.msaa : 1
        sampleCount = wantedMsaa
        preferredFramesPerSecond = config.quality.fps
        drawableSize = CGSize(width: ceil(bounds.width * scale), height: ceil(bounds.height * scale))
        clothWidth = Float(width); clothHeight = Float(height)
        let aspect = Float(height) / clothWidth
        let needRebuild = drop || renderer == nil ||
            renderer?.cloth.aspect != aspect ||
            abs((renderer?.cloth.widthPoints ?? 0) - clothWidth) > 1 ||
            renderer?.cloth.cutout != cutout ||
            renderer?.cloth.config != config ||
            renderer?.sampleCount != wantedMsaa
        if needRebuild, let device {
            do {
                renderer = try ClothRenderer(gpu: device, library: library, aspect: aspect, widthPoints: clothWidth,
                                             cutout: cutout, config: config, sampleCount: wantedMsaa)
                if drop { renderer?.cloth.beginRoll() }
            } catch { NSLog("Renderer init error: %@", error.localizedDescription) }
        }
        renderer?.strandSpacing = strandSpacing
        renderer?.cloth.wind = wind; renderer?.cloth.damping = damping
        renderer?.dye = dye; renderer?.print = print
        smoothBodyOpacity = bodyOpacity; smoothCollarOpacity = 1.0
        renderer?.bodyOpacity = bodyOpacity; renderer?.collarOpacity = 1.0
        renderer?.collarDepth = Float(collar / width)
        previousPointer = nil; lastFrame = CACurrentMediaTime()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let renderer, let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let now = CACurrentMediaTime()
        let dtFrame = max(1e-4, now - lastFrame)
        let pointer = NSEvent.mouseLocation
        if let window {
            let inArea = window.frame.contains(pointer) && (window.screen?.visibleFrame.contains(pointer) ?? false)
            let hit = print == .mesh && inArea && renderer.cloth.nearestPoint(to: BannerCloth.clothPoint(screen: pointer, frame: window.frame, width: clothWidth)) != nil
            window.ignoresMouseEvents = !(hit || renderer.cloth.grabbed != nil || lastCut != nil)
        }
        if let previousPointer, let frame = window?.frame {
            let a = BannerCloth.clothPoint(screen: previousPointer, frame: frame, width: clothWidth)
            let b = BannerCloth.clothPoint(screen: pointer, frame: frame, width: clothWidth)
            renderer.cloth.brush(from: a, to: b, over: dtFrame)
        }
        previousPointer = pointer

        var targetBody = bodyOpacity
        var targetCollar: Float = 1.0
        if fadeOnHover && print != .mesh, let frame = window?.frame {
            let dx = abs(Float(pointer.x - frame.midX))
            let yFromTop = Float(frame.maxY - pointer.y)
            if dx <= clothWidth * 0.54 && yFromTop >= -4 && yFromTop <= clothHeight + 18 {
                let zone = max(30, topHoverZone)
                let topMix = max(0, min(1, 1 - (yFromTop - 36) / max(zone - 36, 20)))
                targetBody = min(bodyOpacity, hoverOpacity + (topHoverOpacity - hoverOpacity) * topMix)
                targetCollar = 1.0 - (1.0 - max(topHoverOpacity, 0.06)) * topMix
            }
        }
        let blend = min(1.0, Float(dtFrame) * (targetBody < smoothBodyOpacity ? 11.0 : 5.5))
        smoothBodyOpacity += (targetBody - smoothBodyOpacity) * blend
        smoothCollarOpacity += (targetCollar - smoothCollarOpacity) * blend
        renderer.bodyOpacity = smoothBodyOpacity
        renderer.collarOpacity = smoothCollarOpacity

        renderer.cloth.advance(seconds: dtFrame)
        let drawStart = CACurrentMediaTime()
        renderer.draw(encoder, viewport: SIMD2(Float(bounds.width), Float(bounds.height)) / clothWidth)
        encoder.endEncoding(); buffer.present(drawable); buffer.commit()
        let drawMs = (CACurrentMediaTime() - drawStart) * 1000.0
        lastFrame = now

        let instFps = min(240, 1.0 / dtFrame)
        smoothFps = smoothFps * 0.85 + instFps * 0.15
        smoothFrameMs = smoothFrameMs * 0.85 + (dtFrame * 1000.0) * 0.15
        if now - statsTimer >= 0.25 {
            statsTimer = now
            let atlasW = renderer.boardTexture?.width ?? renderer.mathematics?.width ?? 0
            BannerStats.shared.record(fps: smoothFps, frameMs: smoothFrameMs, physicsMs: renderer.cloth.lastStepMs,
                                      drawMs: drawMs, cloth: renderer.cloth,
                                      drawableW: drawable.texture.width, drawableH: drawable.texture.height,
                                      msaa: sampleCount, atlasPx: atlasW, style: print.title)
        }
    }
}

final class ScreenBanner {
    let screen: NSScreen
    var window: NSWindow?
    var length: BannerLength = .hidden
    var lastLength: BannerLength = .short
    static let opacities: [Float] = [1, 0.72, 0.46]
    var opacityIndex = 0
    var dyes = Rotation<BannerDye>()
    var prints = Rotation<BannerPrint>()
    var widths = Rotation<BannerWidth>()
    var cutouts = Rotation<BannerCutout>()
    var timer: Timer?
    private var appliedConfig: BannerConfig?

    init(screen: NSScreen) { self.screen = screen }

    var notchSize: CGSize {
        if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            return CGSize(width: r.minX - l.maxX, height: screen.safeAreaInsets.top)
        }
        return CGSize(width: 170, height: max(24, screen.frame.maxY - screen.visibleFrame.maxY))
    }
    var centerX: CGFloat {
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea { return (l.maxX + r.minX) / 2 }
        return screen.frame.midX
    }
    var currentPrint: BannerPrint { prints.current ?? BannerConfig.load().printPool.first ?? .robe }
    var currentDye: BannerDye { dyes.current ?? BannerConfig.load().dyePool.first ?? .garnet }
    var currentCutout: BannerCutout { cutouts.current ?? BannerConfig.load().cutoutPool.first ?? .none }
    var currentWidthFraction: Double {
        if let wf = BannerConfig.load().widthFraction { return wf }
        return (widths.current ?? .nearFull).fraction(notch: notchSize.width, screen: screen.frame.width)
    }
    var currentHeightFraction: Double {
        if let hf = BannerConfig.load().heightFraction { return hf }
        let len = length == .hidden ? lastLength : length
        return len.fraction(notch: notchSize.height, available: screen.frame.height)
    }

    func setNow(print p: BannerPrint?, dye d: BannerDye?, cutout c: BannerCutout?,
                widthFraction wf: Double?, heightFraction hf: Double?, opacity op: Double?) {
        var f = BannerConfig.load()
        var needsLayout = false, needsRebuild = false
        if let p {
            f.pinnedWeave = p == .mesh || p == .grid ? p.key : nil
            _ = prints.advance([p])
        }
        if let d { _ = dyes.advance([d]) }
        if let c { _ = cutouts.advance([c]); needsRebuild = true }
        if let wf { f.widthFraction = wf; needsLayout = true }
        if let hf { f.heightFraction = hf; needsLayout = true }
        if let op { f.opacity = op }
        appliedConfig = f
        f.save()
        if length == .hidden { show(lastLength == .hidden ? .short : lastLength, drop: true, preserve: true); return }
        if needsLayout || needsRebuild { show(lastLength == .hidden ? .short : lastLength, drop: false, preserve: true) }
        else if let canvas = window?.contentView as? BannerCanvas {
            canvas.print = currentPrint; canvas.dye = currentDye
            canvas.bodyOpacity = Float(f.opacity); canvas.fadeOnHover = f.fadeOnHover
            canvas.hoverOpacity = Float(f.hoverOpacity); canvas.topHoverOpacity = Float(f.topHoverOpacity); canvas.topHoverZone = Float(f.topHoverZone)
            if p == .board { canvas.refreshBoard() }
        }
    }

    func scheduleSwitch() {
        timer?.invalidate(); timer = nil
        let mins = BannerConfig.load().minutes
        guard mins > 0, window != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: mins * 60, repeats: false) { [weak self] _ in self?.nextDesign() }
    }

    func nextDesign() {
        guard window != nil else { return show(lastLength) }
        var f = BannerConfig.load()
        let oldW = widths.current, oldC = cutouts.current
        if f.widthFraction != nil { f.widthFraction = nil; f.save() }
        prints.advance(f.printPool); dyes.advance(f.dyePool); widths.advance(f.widthPool); cutouts.advance(f.cutoutPool)
        if widths.current != oldW || cutouts.current != oldC { show(lastLength, drop: widths.current != oldW, preserve: true) }
        else if let c = window?.contentView as? BannerCanvas { c.print = prints.current!; c.dye = dyes.current! }
        scheduleSwitch()
    }

    func applyConfig(rebuild: Bool = false) {
        let f = BannerConfig.load()
        guard window != nil else { return }
        let oldW = widths.current, oldC = cutouts.current
        if appliedConfig?.patterns != f.patterns || appliedConfig?.pinnedWeave != f.pinnedWeave { _ = prints.keep(f.printPool) }
        if appliedConfig?.colours != f.colours { _ = dyes.keep(f.dyePool) }
        if appliedConfig?.widths != f.widths { _ = widths.keep(f.widthPool) }
        if appliedConfig?.cutouts != f.cutouts { _ = cutouts.keep(f.cutoutPool) }
        appliedConfig = f
        if rebuild || widths.current != oldW || cutouts.current != oldC { show(lastLength, drop: false, preserve: true) }
        else if let c = window?.contentView as? BannerCanvas {
            c.strandSpacing = f.strandSpacing; c.wind = Float(f.windStrength); c.damping = Float(f.damping)
            c.bodyOpacity = Float(f.opacity); c.fadeOnHover = f.fadeOnHover
            c.hoverOpacity = Float(f.hoverOpacity); c.topHoverOpacity = Float(f.topHoverOpacity); c.topHoverZone = Float(f.topHoverZone)
            c.print = prints.current!; c.dye = dyes.current!
        }
        scheduleSwitch()
    }

    func showBoard() {
        let f = BannerConfig.load()
        _ = prints.advance([.board]); _ = dyes.keep(f.dyePool)
        _ = widths.advance([.nearFull]); _ = cutouts.keep(f.cutoutPool)
        show(.short, drop: true, preserve: true)
        (window?.contentView as? BannerCanvas)?.refreshBoard()
    }

    func show(_ target: BannerLength, drop: Bool = false, preserve: Bool = false) {
        if target == .hidden {
            timer?.invalidate(); timer = nil
            (window?.contentView as? MTKView)?.isPaused = true
            window?.orderOut(nil); window = nil; length = .hidden
            BannerStats.shared.active = false
            return
        }
        let f = BannerConfig.load()
        appliedConfig = f
        let opening = window == nil
        if opening && !preserve {
            prints.advance(f.printPool); dyes.advance(f.dyePool); widths.advance(f.widthPool); cutouts.advance(f.cutoutPool)
        } else {
            if prints.current == nil { prints.advance(f.printPool) }
            if dyes.current == nil { dyes.advance(f.dyePool) }
            if widths.current == nil { widths.advance(f.widthPool) }
            if cutouts.current == nil { cutouts.advance(f.cutoutPool) }
        }
        let top = screen.frame.maxY, available = screen.frame.height
        let n = notchSize
        let presetH = target.points(notch: n.height, available: available)
        let rawH: CGFloat = f.heightFraction.map { max(n.height + 36, min(available, CGFloat($0) * available)) } ?? presetH
        let clothH = rawH >= available - 4 ? max(80, available - 16) : rawH
        let winH = min(available, clothH + 36)
        let rodW: CGFloat = f.widthFraction.map { max(n.width + 40, min(screen.frame.width, CGFloat($0) * screen.frame.width)) }
            ?? (widths.current ?? .nearFull).rod(notch: n.width, screen: screen.frame.width)
        let clothW = rodW / CGFloat(BannerCloth.rodSpan)
        let shift = CGFloat(f.offset) * max(0, (screen.frame.width - rodW) / 2)
        let winW = min(screen.frame.width - 2 * abs(shift), 2 * clothH + clothW * 1.1)
        let frame = NSRect(x: centerX + shift - winW / 2, y: top - winH, width: winW, height: winH)

        if opening {
            guard let dev = MTLCreateSystemDefaultDevice(),
                  let view = BannerCanvas(frame: NSRect(origin: .zero, size: frame.size), metal: dev) else { return }
            let w = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
            w.ignoresMouseEvents = true; w.level = .statusBar; w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.contentView = view
            window = w
        }
        window?.setFrame(frame, display: false)
        if let canvas = window?.contentView as? BannerCanvas {
            canvas.strandSpacing = f.strandSpacing; canvas.wind = Float(f.windStrength); canvas.damping = Float(f.damping)
            canvas.dye = dyes.current ?? .garnet; canvas.print = prints.current ?? .robe
            canvas.bodyOpacity = Float(f.opacity); canvas.fadeOnHover = f.fadeOnHover
            canvas.hoverOpacity = Float(f.hoverOpacity); canvas.topHoverOpacity = Float(f.topHoverOpacity); canvas.topHoverZone = Float(f.topHoverZone)
            canvas.unfold(to: clothH, width: clothW, collar: n.height,
                          cutout: cutouts.current ?? .none, config: f.physicsConfig, drop: opening || drop)
        }
        window?.orderFrontRegardless()
        length = target; lastLength = target
        if opening { scheduleSwitch() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var banners: [ScreenBanner] = []
    var statusItem: NSStatusItem?
    lazy var menu: NSMenu = { let m = NSMenu(); m.delegate = self; m.autoenablesItems = false; return m }()
    var statsWindow: NSPanel?
    var settingsWindow: NSPanel?
    var settingsStore: SettingsStore?
    var hotKeyRefs: [EventHotKeyRef] = []
    var hotKeyHandler: EventHandlerRef?
    var startWithBoard = false

    var activeBanner: ScreenBanner? {
        let m = NSEvent.mouseLocation
        return banners.first(where: { $0.screen.frame.contains(m) }) ?? banners.first
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        banners = NSScreen.screens.map { ScreenBanner(screen: $0) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "flag.fill", accessibilityDescription: "NotchBanner")
        item.button?.toolTip = "Click: Banner Studio window · Right-click: quick menu · ⌃⌥⌘B toggle"
        item.button?.target = self
        item.button?.action = #selector(statusClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        registerHotkeys()
        if startWithBoard { activeBanner?.showBoard() }
        else { activeBanner?.show(.short, drop: true) }
    }

    @objc func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
        } else {
            openSettings()
        }
    }

    func registerHotkeys() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let sig: OSType = 0x4E424E52
        InstallEventHandler(GetApplicationEventTarget(), { _, ev, ctx in
            guard let ev, let ctx else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let app = Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue()
            guard let b = app.activeBanner else { return noErr }
            switch id.id {
            case 1: b.show(b.length == .hidden ? b.lastLength : .hidden)
            case 2:
                let hs: [BannerLength] = [.ultraShort, .short, .half, .full]
                let next = hs[((hs.firstIndex(of: b.lastLength) ?? 1) + 1) % hs.count]
                var f = BannerConfig.load(); f.heightFraction = nil; f.save()
                b.show(next)
            case 3:
                b.opacityIndex = (b.opacityIndex + 1) % ScreenBanner.opacities.count
                var f = BannerConfig.load(); f.opacity = Double(ScreenBanner.opacities[b.opacityIndex]); f.save()
                if b.length == .hidden { b.show(b.lastLength) }
                (b.window?.contentView as? BannerCanvas)?.bodyOpacity = ScreenBanner.opacities[b.opacityIndex]
            default: b.nextDesign()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        for (i, k) in [kVK_ANSI_B, kVK_ANSI_H, kVK_ANSI_T, kVK_ANSI_N].enumerated() {
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(UInt32(k), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: sig, id: UInt32(i + 1)), GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                hotKeyRefs.append(ref)
            }
        }
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        guard let b = activeBanner else { return }
        let f = BannerConfig.load()
        m.removeAllItems()
        func add(_ t: String, _ a: Selector?, tag: Int = 0, on: Bool = false, to: NSMenu? = nil) {
            let it = (to ?? m).addItem(withTitle: t, action: a, keyEquivalent: "")
            it.target = self; it.tag = tag; it.state = on ? .on : .off
            if a == nil { it.isEnabled = false }
        }
        func sub(_ t: String) -> NSMenu {
            let it = m.addItem(withTitle: t, action: nil, keyEquivalent: ""); let sm = NSMenu(); sm.autoenablesItems = false
            m.setSubmenu(sm, for: it); return sm
        }
        add("Open Banner Studio Window…", #selector(openSettings))
        m.addItem(.separator())
        add(b.length == .hidden ? "Show Banner   ⌃⌥⌘B" : "Hide Banner   ⌃⌥⌘B", #selector(toggleBanner))
        add("Next Design   ⌃⌥⌘N", #selector(nextDesign))
        add("Show Live 4K Board", #selector(showBoard))
        add("Send Wind Gust", #selector(sendGust))
        m.addItem(.separator())
        let hSub = sub("Height")
        for l in [BannerLength.ultraShort, .short, .half, .full] { add(l.title, #selector(setHeight(_:)), tag: l.rawValue, on: f.heightFraction == nil && b.lastLength == l, to: hSub) }
        let qSub = sub("Quality")
        for (i, q) in BannerQuality.allCases.enumerated() { add(q.title, #selector(setQuality(_:)), tag: i, on: f.quality == q.rawValue, to: qSub) }
        let cSub = sub("Bottom Cutout")
        for (i, c) in BannerCutout.allCases.enumerated() { add(c.title, #selector(toggleCutout(_:)), tag: i, on: f.cutouts.contains(c.rawValue), to: cSub) }
        add("Transparent on mouse hover", #selector(toggleHoverFade), on: f.fadeOnHover)
        m.addItem(.separator())
        add("Diagnostics HUD (FPS)", #selector(toggleStats), on: statsWindow?.isVisible == true)
        add("Quit NotchBanner", #selector(NSApplication.terminate(_:)))
    }

    func edit(rebuild: Bool = false, _ fn: (inout BannerConfig) -> Void) {
        var f = BannerConfig.load(); fn(&f)
        guard !f.patterns.isEmpty, !f.colours.isEmpty, !f.widths.isEmpty, !f.cutouts.isEmpty else { return }
        f.save(); banners.forEach { $0.applyConfig(rebuild: rebuild) }
    }
    func flip(_ list: inout [String], _ k: String) { if let i = list.firstIndex(of: k) { list.remove(at: i) } else { list.append(k) } }

    @objc func toggleBanner() { activeBanner?.show(activeBanner?.length == .hidden ? (activeBanner?.lastLength ?? .short) : .hidden) }
    @objc func nextDesign() { activeBanner?.nextDesign() }
    @objc func showBoard() { activeBanner?.showBoard() }
    @objc func sendGust() { (activeBanner?.window?.contentView as? BannerCanvas)?.gust() }
    @objc func toggleHoverFade() { edit { $0.fadeOnHover.toggle() } }
    @objc func setHeight(_ i: NSMenuItem) { if let l = BannerLength(rawValue: i.tag) { var f = BannerConfig.load(); f.heightFraction = nil; f.save(); activeBanner?.show(l) } }
    @objc func setQuality(_ i: NSMenuItem) { edit(rebuild: true) { $0.quality = BannerQuality.allCases[i.tag].rawValue } }
    @objc func toggleCutout(_ i: NSMenuItem) { edit(rebuild: true) { flip(&$0.cutouts, BannerCutout.allCases[i.tag].rawValue) } }

    @objc func toggleStats() {
        if let w = statsWindow, w.isVisible { w.orderOut(nil); return }
        if statsWindow == nil {
            let p = NSPanel(contentRect: NSRect(x: 40, y: 80, width: 318, height: 245),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1); p.isMovableByWindowBackground = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: BannerStatsHUDView { [weak p] in p?.orderOut(nil) })
            statsWindow = p
        }
        if let s = (activeBanner?.screen ?? NSScreen.main)?.visibleFrame {
            statsWindow?.setFrameOrigin(NSPoint(x: s.maxX - 342, y: s.minY + 34))
        }
        statsWindow?.orderFrontRegardless()
    }

    @objc func openSettings() {
        if let w = settingsWindow, w.isVisible { w.orderOut(nil); return }
        let b = activeBanner
        let scr = b?.screen.frame.size ?? NSSize(width: 1512, height: 982)
        let nch = b?.notchSize ?? NSSize(width: 190, height: 37)
        let store = SettingsStore(
            settings: BannerConfig.load(),
            isVisible: (b?.length ?? .hidden) != .hidden,
            print: b?.currentPrint ?? .robe,
            dye: b?.currentDye ?? .garnet,
            cutout: b?.currentCutout ?? .none,
            widthFraction: b?.currentWidthFraction ?? 0.85,
            heightFraction: b?.currentHeightFraction ?? 0.35,
            screen: scr,
            notch: nch
        )
        settingsStore = store
        let view = BannerSettingsView(
            m: store,
            onSave: { [weak self] cfg, rebuild in cfg.save(); self?.banners.forEach { $0.applyConfig(rebuild: rebuild) } },
            onSetNow: { [weak self] p, d, c, wf, hf, op in self?.activeBanner?.setNow(print: p, dye: d, cutout: c, widthFraction: wf, heightFraction: hf, opacity: op) },
            onToggleVisible: { [weak self] in self?.toggleBanner() },
            onNext: { [weak self] in
                guard let target = self?.activeBanner else { return }
                target.nextDesign()
                store.currentPrint = target.currentPrint; store.currentDye = target.currentDye
                store.currentCutout = target.currentCutout; store.widthFraction = target.currentWidthFraction
                store.isVisible = target.length != .hidden
            },
            onGust: { [weak self] in self?.sendGust() },
            onToggleStats: { [weak self] in self?.toggleStats() },
            onShowBoard: { [weak self] in self?.showBoard(); store.currentPrint = .board; store.isVisible = true },
            onClose: { [weak self] in self?.settingsWindow?.orderOut(nil) },
            onMend: { [weak b] in guard let b else { return }; b.show(b.lastLength, drop: true, preserve: true) }
        )
        if settingsWindow == nil {
            let p = NSPanel(contentRect: NSRect(x: 100, y: 120, width: 440, height: 540),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1); p.isMovableByWindowBackground = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            settingsWindow = p
        }
        let host = NSHostingView(rootView: view)
        let usable = (b?.screen ?? NSScreen.main)?.visibleFrame.height ?? 760
        settingsWindow?.setContentSize(NSSize(width: 440, height: min(730, usable - 32)))
        settingsWindow?.contentView = host
        if let s = (b?.screen ?? NSScreen.main)?.visibleFrame {
            settingsWindow?.setFrameOrigin(NSPoint(x: s.midX - 220, y: s.midY - (settingsWindow?.frame.height ?? 600) / 2))
        }
        settingsWindow?.orderFrontRegardless()
    }
}

// MARK: - Headless Metal Cinema Demo Recorder (1920×1080 @ 60fps on Apple Silicon GPU!)

enum DemoRecorder {
    static func run(outputPath: String, stillsDir: String?, interactionDemo: Bool = false, weaveDemo: Bool = false) throws {
        guard let gpu = MTLCreateSystemDefaultDevice(),
              let queue = gpu.makeCommandQueue() else {
            throw NSError(domain: "NotchBanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal GPU unavailable"])
        }
        let shaderSrc = try String(contentsOf: AppPaths.resource("banner.metal"), encoding: .utf8)
        let library = try gpu.makeLibrary(source: shaderSrc, options: nil)

        let W = 1920, H = 1080, fps = (interactionDemo || weaveDemo) ? 30 : 60
        let totalSec = weaveDemo ? 20 : (interactionDemo ? 18 : 30)
        let totalFrames = totalSec * fps
        let msaa = gpu.supportsTextureSampleCount(4) ? 4 : 1

        // Offscreen MSAA + resolve + depth textures
        let colorDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        colorDesc.usage = [.renderTarget, .shaderRead]
        colorDesc.storageMode = .shared
        let resolveTex = gpu.makeTexture(descriptor: colorDesc)!

        let msaaDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        msaaDesc.textureType = msaa > 1 ? .type2DMultisample : .type2D
        msaaDesc.sampleCount = msaa
        msaaDesc.usage = .renderTarget
        msaaDesc.storageMode = .private
        let msaaTex = msaa > 1 ? gpu.makeTexture(descriptor: msaaDesc)! : resolveTex

        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: W, height: H, mipmapped: false)
        depthDesc.textureType = msaa > 1 ? .type2DMultisample : .type2D
        depthDesc.sampleCount = msaa
        depthDesc.usage = .renderTarget
        depthDesc.storageMode = .private
        let depthTex = gpu.makeTexture(descriptor: depthDesc)!

        // Pre-render sleek dark macOS desktop backdrop + menu bar + MacBook notch once
        let bgPixels = renderBackdrop(width: W, height: H, plain: interactionDemo || weaveDemo)

        let outURL = URL(fileURLWithPath: outputPath)
        try? FileManager.default.removeItem(at: outURL)
        try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let stillsDir { try? FileManager.default.createDirectory(atPath: stillsDir, withIntermediateDirectories: true) }

        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: W,
            AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 14_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: W,
                kCVPixelBufferHeightKey as String: H
            ]
        )
        writer.add(input)
        writer.shouldOptimizeForNetworkUse = true
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let clothWidthPt: Float = interactionDemo ? 1200 : 1660
        let clothHeightPt: Float = 560.0
        let aspect = clothHeightPt / clothWidthPt
        let viewport = SIMD2<Float>(Float(W), Float(H)) / clothWidthPt
        let highCfg = BannerPhysics(quality: .xhigh, scale: 1.0, mass: 0.85, stiffness: 1.0, damping: 0.65, pleats: 1.0)

        func makeRenderer(cutout: BannerCutout, print: BannerPrint, dye: BannerDye, roll: Bool, cfg: BannerPhysics = highCfg) throws -> ClothRenderer {
            let r = try ClothRenderer(gpu: gpu, library: library, aspect: aspect, widthPoints: clothWidthPt, cutout: cutout, config: cfg, sampleCount: msaa)
            r.collarDepth = 38.0 / clothWidthPt
            r.dye = dye
            r.print = print
            r.cloth.wind = 1.15
            if roll { r.cloth.beginRoll() }
            else { for _ in 0..<90 { r.cloth.advance(seconds: 1.0 / 60.0) } }
            return r
        }

        let demoBoard = BannerBoard.Payload(
            eyebrow: "NOTCH BANNER · LIVE 4K BOARD",
            title: "Morning Briefing · Ship v1.0 & Performance Audit",
            subtitle: nil,
            sections: [
                SectionCompat("TODAY'S DIGEST", [
                    "XPBD heavy velvet engine: 60–120 FPS at 4× MSAA",
                    "8K mathematical atlases + zero-pixel micro-pile shader",
                    "Straight hem default + 4 heraldic cutout shapes"
                ]),
                SectionCompat("BUILD & DEPLOY", [
                    "Apple Silicon Metal GPU: 2.1 ms sim · 0.1 ms draw",
                    "Standalone menu-bar app + JSON board plugin API",
                    "All 6 quality tiers verified (Low → Ultra 16k nodes)"
                ]),
                SectionCompat("CONTROLS", [
                    "⌃⌥⌘B Toggle banner  ·  ⌃⌥⌘N Next design",
                    "Cursor sweeps naturally ripple the velvet cloth",
                    "Write ~/.config/notch-banner/board.json for live data"
                ])
            ],
            footer: "Apple Silicon Metal   ·   3840 px Live Board   ·   github.com/calmmage/notch-banner"
        )

        var renderer = try makeRenderer(cutout: .none, print: interactionDemo ? .mandala : .robe, dye: .garnet, roll: true)
        var clothBytes = [UInt8](repeating: 0, count: W * H * 4)
        var frameBytes = [UInt8](repeating: 0, count: W * H * 4)
        var grabStart = SIMD2<Float>.zero
        var currentScene = weaveDemo ? -1 : 0
        var prevCursor: SIMD2<Float>?
        var fpsHistory: [Double] = (0..<48).map { _ in 60.0 }

        print("Recording \(totalSec)s 1080p\(fps) Metal cinema demo on \(gpu.name) → \(outputPath)")
        let startWall = CACurrentMediaTime()

        for frameIdx in 0..<totalFrames {
            let t = Double(frameIdx) / Double(fps)
            var caption = ""
            var subcaption = ""
            var cursorPt: CGPoint?
            var showHUD = false

            var cameraShift = 0.0
            if weaveDemo {
                let scene = min(4, Int(t / 4))
                let phases = [StrandSpacing.coarse, .fine, .dense, .dense, .fine]
                let meshes = [ClothResolution.medium, .medium, .fine, .fine, .fine]
                if currentScene != scene {
                    var cfg = highCfg
                    cfg.model = scene < 2 ? .original : .tension
                    cfg.resolution = meshes[scene]
                    renderer = try makeRenderer(cutout: .none, print: scene == 4 ? .grid : .mesh, dye: .midnight, roll: false, cfg: cfg)
                    renderer.strandSpacing = phases[scene]
                    currentScene = scene
                    prevCursor = nil
                    Swift.print("Scene \(scene): \(renderer.cloth.columns) × \(renderer.cloth.rows) nodes, \(renderer.cloth.triangleCount) faces")
                }
                caption = ["Open net · coarse strands", "Same geometry · finer strands", "Tension net · grab and hold", "Cutting the dense net", "Grid cloth · woven surface"][scene]
                subcaption = "\(phases[scene].points) pt yarn spacing  /  \(renderer.cloth.columns) × \(renderer.cloth.rows) nodes  /  \(scene < 2 ? "original velvet physics" : "tension net physics")"
                let phase = Float(t.truncatingRemainder(dividingBy: 4))
                let cloth = renderer.cloth
                var cursor: SIMD2<Float>?
                if scene == 2, phase > 0.3, phase < 3.3 {
                    if cloth.grabbed == nil {
                        grabStart = cloth.projected((cloth.rows * 2 / 3) * cloth.columns + cloth.columns / 2)
                        cloth.grab(at: grabStart)
                    }
                    cursor = grabStart + SIMD2(0.15, -0.105) * min(1, (phase - 0.3) / 1.5)
                    if let cursor { cloth.drag(to: cursor) }
                } else if scene == 3, phase > 0.3, phase < 3.5 {
                    let u = min(1, (phase - 0.3) / 2.5)
                    cursor = SIMD2(-0.45 + 0.78 * u, 0.15 + 0.035 * sin(u * .pi))
                    if let prevCursor, let cursor { cloth.cut(from: prevCursor, to: cursor) }
                    prevCursor = cursor
                } else { cloth.releaseGrab() }
                if let cursor { cursorPt = CGPoint(x: CGFloat(W)/2 + CGFloat(cursor.x * clothWidthPt), y: CGFloat(cursor.y * clothWidthPt)) }
            } else if interactionDemo {
                if t < 3 {
                    caption = "Position"
                    subcaption = "Banner Studio  /  Position"
                    cameraShift = min(1, max(0, t - 0.8)) * 320
                } else if t < 6 {
                    if currentScene != 1 {
                        var cfg = highCfg
                        cfg.split = true
                        renderer = try makeRenderer(cutout: .none, print: .mosaic, dye: .midnight, roll: false, cfg: cfg)
                        currentScene = 1
                    }
                    cameraShift = 320
                    caption = "Split the middle"
                    subcaption = "Two panels share the rod. The centre stays open."
                } else if t < 15 {
                    if currentScene != 2 {
                        var cfg = highCfg
                        cfg.quality = .low
                        renderer = try makeRenderer(cutout: .none, print: .mesh, dye: .pine, roll: false, cfg: cfg)
                        currentScene = 2
                    }
                    let cloth = renderer.cloth
                    var point: SIMD2<Float>?
                    if t < 10.5 {
                        caption = "Grab a knot"
                        subcaption = "Mesh  /  Left-drag and hold. Release to let go."
                        if t >= 6.8 && t < 9.7 {
                            if cloth.grabbed == nil {
                                grabStart = cloth.projected((cloth.rows * 2 / 3) * cloth.columns + cloth.columns / 2)
                                cloth.grab(at: grabStart)
                            }
                            let fraction = Float(min(1, (t - 6.8) / 1.5))
                            point = grabStart + SIMD2(0.23, -0.19) * fraction
                            cloth.drag(to: point!)
                        } else { cloth.releaseGrab() }
                    } else {
                        caption = "Cut the net"
                        subcaption = "Right-drag across the strands."
                        let progress = Float(min(1, (t - 10.5) / 2.9))
                        let pos = SIMD2<Float>(-0.38 + progress * 0.86, 0.22 + sin(progress * .pi) * 0.045)
                        if let prevCursor, progress < 1 { cloth.cut(from: prevCursor, to: pos) }
                        prevCursor = pos
                        if progress < 1 { point = pos }
                    }
                    if let point { cursorPt = CGPoint(x: CGFloat(W) / 2 + CGFloat(point.x * clothWidthPt), y: CGFloat(point.y * clothWidthPt)) }
                } else {
                    if currentScene != 3 {
                        renderer = try makeRenderer(cutout: .none, print: .ink, dye: .garnet, roll: false)
                        currentScene = 3
                    }
                    caption = "Sumi-e ink"
                    subcaption = "Flag in the menu bar  /  Banner Studio  /  Now (Live)"
                }
            } else if t < 6.0 {
                caption = "Giant Theater Velvet · Unrolling from the Notch"
                subcaption = "Meters-scale XPBD cloth · Straight hem default · Heavy velvet pleats"
            } else if t < 11.0 {
                if currentScene != 1 {
                    currentScene = 1
                    renderer.cloth.gust()
                }
                if t > 8.5 && renderer.dye != .midnight { renderer.dye = .midnight }
                caption = "Interactive Cursor Brush & Strong Wind Combat"
                subcaption = "Weighted hem + LRA tether · Heavy inertia fights rolling gusts"
                // Smooth arc sweeping across the lower velvet curtain
                let p = Float((t - 6.3) / 3.8)
                if p >= 0 && p <= 1 {
                    let sx = CGFloat(320 + p * 1280)
                    let sy = CGFloat(390 + sin(p * Float.pi * 2.5) * 95)
                    cursorPt = CGPoint(x: sx, y: sy)
                    let cur = SIMD2<Float>(Float(sx - CGFloat(W) * 0.5), Float(sy)) / clothWidthPt
                    if let prev = prevCursor { renderer.cloth.brush(from: prev, to: cur, over: 1.0 / Double(fps)) }
                    prevCursor = cur
                } else { prevCursor = nil }
            } else if t < 16.0 {
                prevCursor = nil
                if currentScene != 2 {
                    currentScene = 2
                    renderer = try makeRenderer(cutout: .none, print: .lorenz, dye: .garnet, roll: false)
                    renderer.cloth.gust()
                }
                if t > 13.5 && renderer.print != .bifurcation { renderer.print = .bifurcation; renderer.dye = .black }
                caption = "8K Mathematical Atlases · Zero-Pixel Velvet Micro-Pile"
                subcaption = "8192×8192 plates · 16× anisotropic filtering · 4× MSAA"
            } else if t < 21.0 {
                if currentScene != 3 {
                    currentScene = 3
                    renderer = try makeRenderer(cutout: .arch, print: .robe, dye: .pine, roll: false)
                } else if abs(t - 17.7) < 0.01 {
                    renderer = try makeRenderer(cutout: .waves, print: .silk, dye: .midnight, roll: false)
                } else if abs(t - 19.3) < 0.01 {
                    renderer = try makeRenderer(cutout: .swallowtail, print: .robe, dye: .garnet, roll: false)
                }
                caption = "5 Bottom Cutout Shapes"
                subcaption = "Straight (default) · Arched · Scalloped · Swallowtail · Pointed"
            } else if t < 26.0 {
                if currentScene != 4 {
                    currentScene = 4
                    renderer = try makeRenderer(cutout: .none, print: .board, dye: .midnight, roll: true)
                    renderer.refreshBoardIfNeeded(force: true, payload: demoBoard)
                }
                caption = "Live 4K Info Board · Woven Directly on Waving Cloth"
                subcaption = "Daily digests, agent summaries & dashboards via board.json plugin API"
            } else {
                if currentScene != 5 {
                    currentScene = 5
                    renderer = try makeRenderer(cutout: .none, print: .notebook, dye: .garnet, roll: false)
                    renderer.cloth.gust()
                }
                showHUD = true
                caption = "6 Quality Tiers (Low → Ultra) · Live Physics & FPS HUD"
                subcaption = "Tune wind, scale, mass, stiffness, damping & pleats in real time"
            }

            renderer.cloth.advance(seconds: 1.0 / Double(fps))
            let simMs = renderer.cloth.lastStepMs
            fpsHistory.append(min(120, 60.0 + sin(t * 3.1) * 0.4))
            if fpsHistory.count > 60 { fpsHistory.removeFirst() }

            // Render cloth offscreen on Metal GPU
            let pass = MTLRenderPassDescriptor()
            if msaa > 1 {
                pass.colorAttachments[0].texture = msaaTex
                pass.colorAttachments[0].resolveTexture = resolveTex
                pass.colorAttachments[0].storeAction = .multisampleResolve
            } else {
                pass.colorAttachments[0].texture = resolveTex
                pass.colorAttachments[0].storeAction = .store
            }
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            pass.depthAttachment.texture = depthTex
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1.0
            pass.depthAttachment.storeAction = .dontCare

            let cb = queue.makeCommandBuffer()!
            let enc = cb.makeRenderCommandEncoder(descriptor: pass)!
            if cameraShift != 0 { enc.setViewport(MTLViewport(originX: cameraShift, originY: 0, width: Double(W), height: Double(H), znear: 0, zfar: 1)) }
            renderer.draw(enc, viewport: viewport)
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()

            resolveTex.getBytes(&clothBytes, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0)

            // Alpha-composite premultiplied BGRA cloth over macOS desktop backdrop
            frameBytes.withUnsafeMutableBufferPointer { dst in
                bgPixels.withUnsafeBufferPointer { bg in
                    clothBytes.withUnsafeBufferPointer { fg in
                        let n = W * H
                        for i in 0..<n {
                            let o = i * 4
                            let a = Int(fg[o + 3])
                            if a == 0 {
                                dst[o] = bg[o]; dst[o + 1] = bg[o + 1]; dst[o + 2] = bg[o + 2]; dst[o + 3] = 255
                            } else if a == 255 {
                                dst[o] = fg[o]; dst[o + 1] = fg[o + 1]; dst[o + 2] = fg[o + 2]; dst[o + 3] = 255
                            } else {
                                let inv = 255 - a
                                dst[o]     = UInt8(min(255, Int(fg[o])     + (Int(bg[o])     * inv) / 255))
                                dst[o + 1] = UInt8(min(255, Int(fg[o + 1]) + (Int(bg[o + 1]) * inv) / 255))
                                dst[o + 2] = UInt8(min(255, Int(fg[o + 2]) + (Int(bg[o + 2]) * inv) / 255))
                                dst[o + 3] = 255
                            }
                        }
                    }
                }
            }

            // Draw MacBook Pro notch on top + subtle cinema caption pill + cursor / Diagnostics HUD
            drawOverlay(into: &frameBytes, width: W, height: H, caption: caption, subcaption: subcaption,
                        cursor: cursorPt, showHUD: showHUD, cloth: renderer.cloth, simMs: simMs, msaa: msaa, fpsHistory: fpsHistory)

            // Save key PNG stills for GitHub README
            if let stillsDir {
                if frameIdx == 210 { savePNG(frameBytes, W, H, "\(stillsDir)/hero.png") }
                else if frameIdx == 760 { savePNG(frameBytes, W, H, "\(stillsDir)/plates.png") }
                else if frameIdx == 1020 { savePNG(frameBytes, W, H, "\(stillsDir)/cutouts.png") }
                else if frameIdx == 1440 { savePNG(frameBytes, W, H, "\(stillsDir)/board.png") }
                else if frameIdx == 1710 { savePNG(frameBytes, W, H, "\(stillsDir)/hud.png") }
            }

            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            if let pb {
                CVPixelBufferLockBaseAddress(pb, [])
                if let base = CVPixelBufferGetBaseAddress(pb) {
                    let rowBytes = CVPixelBufferGetBytesPerRow(pb)
                    frameBytes.withUnsafeBytes { raw in
                        for row in 0..<H {
                            memcpy(base.advanced(by: row * rowBytes), raw.baseAddress!.advanced(by: row * W * 4), W * 4)
                        }
                    }
                }
                CVPixelBufferUnlockBaseAddress(pb, [])
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frameIdx), timescale: CMTimeScale(fps)))
            }
            if (frameIdx + 1) % 300 == 0 {
                print(String(format: "  %d / %d frames (%.1fs elapsed)", frameIdx + 1, totalFrames, CACurrentMediaTime() - startWall))
            }
        }

        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "NotchBanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter failed"])
        }
        print(String(format: "Done! Wrote %@ in %.1fs", outputPath, CACurrentMediaTime() - startWall))
    }

    static func SectionCompat(_ h: String, _ items: [String]) -> BannerBoard.Section { BannerBoard.Section(heading: h, items: items) }

    static func renderBackdrop(width W: Int, height H: Int, plain: Bool) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: W * H * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        bytes.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                      space: cs, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }
            ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            defer { NSGraphicsContext.restoreGraphicsState() }

            // Deep refined macOS desktop dusk gradient
            let grad = NSGradient(colors: [
                NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.11, alpha: 1),
                NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.17, alpha: 1),
                NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1)
            ])!
            grad.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 125)

            // Soft architectural light orbs
            let orb1 = NSGradient(colors: [NSColor(calibratedRed: 0.24, green: 0.16, blue: 0.34, alpha: 0.22), .clear])!
            orb1.draw(fromCenter: NSPoint(x: 340, y: 780), radius: 0, toCenter: NSPoint(x: 340, y: 780), radius: 520, options: [])
            let orb2 = NSGradient(colors: [NSColor(calibratedRed: 0.12, green: 0.26, blue: 0.34, alpha: 0.22), .clear])!
            orb2.draw(fromCenter: NSPoint(x: 1580, y: 760), radius: 0, toCenter: NSPoint(x: 1580, y: 760), radius: 540, options: [])

            if plain { return }
            // Subtle mock code-editor window below so the banner reads immediately as a real desktop overlay
            let winRect = NSRect(x: 210, y: 470, width: 1500, height: 520)
            let winPath = NSBezierPath(roundedRect: winRect, xRadius: 14, yRadius: 14)
            NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.86).setFill(); winPath.fill()
            NSColor(calibratedWhite: 1, alpha: 0.09).setStroke(); winPath.lineWidth = 1.2; winPath.stroke()
            for (i, c) in [NSColor(calibratedRed: 0.96, green: 0.37, blue: 0.35, alpha: 0.85),
                           NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.25, alpha: 0.85),
                           NSColor(calibratedRed: 0.28, green: 0.80, blue: 0.38, alpha: 0.85)].enumerated() {
                c.setFill()
                NSBezierPath(ovalIn: NSRect(x: 232 + i * 20, y: 486, width: 12, height: 12)).fill()
            }
            let codeFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
            let lines = [
                "// NotchBanner — Real-time XPBD Velvet Cloth & 8K Metal Shader",
                "$ brew install librsvg && make app && make install",
                "✓ Built NotchBanner.app (Apple Silicon Metal · 4× MSAA · 60–120 FPS)",
                "✓ Mesh: 129 × 44 (5,676 nodes · 10,800 triangles · 32,700 XPBD constraints)",
                "✓ Live 4K Board API: ~/.config/notch-banner/board.json"
            ]
            for (i, line) in lines.enumerated() {
                let col = i == 0 ? NSColor(calibratedWhite: 0.55, alpha: 0.8) :
                          (line.hasPrefix("✓") ? NSColor(calibratedRed: 0.45, green: 0.90, blue: 0.62, alpha: 0.85) : NSColor(calibratedWhite: 0.85, alpha: 0.85))
                (line as NSString).draw(at: NSPoint(x: 254, y: 540 + CGFloat(i) * 34), withAttributes: [.font: codeFont, .foregroundColor: col])
            }

            // macOS top menu bar
            NSColor(calibratedWhite: 0.04, alpha: 0.65).setFill()
            NSRect(x: 0, y: 0, width: W, height: 36).fill()
            let mbFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
            let mbAttr: [NSAttributedString.Key: Any] = [.font: mbFont, .foregroundColor: NSColor.white.withAlphaComponent(0.88)]
            ("   NotchBanner   File   Edit   View   Window" as NSString).draw(at: NSPoint(x: 22, y: 9), withAttributes: mbAttr)
            ("⚑   Wi-Fi   98%   Sat 18:30" as NSString).draw(at: NSPoint(x: W - 245, y: 9), withAttributes: mbAttr)
        }
        return bytes
    }

    static func drawOverlay(into bytes: inout [UInt8], width W: Int, height H: Int, caption: String, subcaption: String,
                            cursor: CGPoint?, showHUD: Bool, cloth: BannerCloth, simMs: Double, msaa: Int, fpsHistory: [Double]) {
        let cs = CGColorSpaceCreateDeviceRGB()
        bytes.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                      space: cs, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }
            ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            defer { NSGraphicsContext.restoreGraphicsState() }

            // Authentic MacBook Pro notch centered at top edge
            let notchW: CGFloat = 220, notchH: CGFloat = 38
            let notchRect = NSRect(x: (CGFloat(W) - notchW) / 2, y: -12, width: notchW, height: notchH + 12)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: notchRect, xRadius: 12, yRadius: 12).fill()

            // Glowing cursor ripple indicator during cursor brush scene
            if let c = cursor {
                let glow = NSGradient(colors: [NSColor(calibratedRed: 0.98, green: 0.84, blue: 0.48, alpha: 0.55), .clear])!
                glow.draw(fromCenter: c, radius: 0, toCenter: c, radius: 36, options: [])
                NSColor.white.setFill()
                NSBezierPath(ovalIn: NSRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)).fill()
            }

            // Cinema caption pill bottom-left
            let pillRect = NSRect(x: 48, y: CGFloat(H) - 108, width: 760, height: 68)
            let pill = NSBezierPath(roundedRect: pillRect, xRadius: 14, yRadius: 14)
            NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.07, alpha: 0.84).setFill(); pill.fill()
            NSColor(calibratedRed: 0.92, green: 0.78, blue: 0.48, alpha: 0.35).setStroke(); pill.lineWidth = 1.2; pill.stroke()
            (caption as NSString).draw(at: NSPoint(x: 70, y: CGFloat(H) - 96), withAttributes: [
                .font: NSFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.91, alpha: 0.98)
            ])
            (subcaption as NSString).draw(at: NSPoint(x: 70, y: CGFloat(H) - 67), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor(calibratedRed: 0.90, green: 0.78, blue: 0.52, alpha: 0.88)
            ])

            // Live Diagnostics HUD in scene 6
            if showHUD {
                let hud = NSRect(x: CGFloat(W) - 410, y: CGFloat(H) - 310, width: 360, height: 270)
                let hp = NSBezierPath(roundedRect: hud, xRadius: 14, yRadius: 14)
                NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.08, alpha: 0.92).setFill(); hp.fill()
                NSColor.white.withAlphaComponent(0.18).setStroke(); hp.lineWidth = 1.2; hp.stroke()
                ("NOTCH BANNER · DIAGNOSTICS" as NSString).draw(at: NSPoint(x: hud.minX + 18, y: hud.minY + 16), withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.white.withAlphaComponent(0.65)
                ])
                ("60 FPS" as NSString).draw(at: NSPoint(x: hud.minX + 18, y: hud.minY + 40), withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 34, weight: .bold), .foregroundColor: NSColor(calibratedRed: 0.45, green: 0.92, blue: 0.58, alpha: 1)
                ])
                (String(format: "Sim %.2f ms · 4× MSAA", simMs) as NSString).draw(at: NSPoint(x: hud.minX + 175, y: hud.minY + 52), withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.8)
                ])
                // Sparkline
                let sp = NSRect(x: hud.minX + 18, y: hud.minY + 90, width: hud.width - 36, height: 34)
                NSColor.white.withAlphaComponent(0.06).setFill(); NSBezierPath(roundedRect: sp, xRadius: 5, yRadius: 5).fill()
                let line = NSBezierPath()
                for (i, v) in fpsHistory.enumerated() {
                    let x = sp.minX + sp.width * CGFloat(i) / CGFloat(max(1, fpsHistory.count - 1))
                    let y = sp.maxY - sp.height * CGFloat(min(v, 75) / 75.0)
                    if i == 0 { line.move(to: NSPoint(x: x, y: y)) } else { line.line(to: NSPoint(x: x, y: y)) }
                }
                NSColor(calibratedRed: 0.45, green: 0.92, blue: 0.58, alpha: 1).setStroke(); line.lineWidth = 2; line.stroke()
                let rows = [
                    "Mesh      \(cloth.columns) × \(cloth.rows) (\(cloth.nodes.count) nodes)",
                    "XPBD      \(cloth.joints.count) constraints · \(cloth.triangleCount) tris",
                    "Drawable  1920 × 1080 · \(msaa)× MSAA",
                    "Atlas     8192 × 8192 px (4K/plate)",
                    String(format: "Curtain   %.1fm × %.1fm · %.2f kg/m²", cloth.metersPerWidth, cloth.heightMeters, cloth.config.mass)
                ]
                for (i, r) in rows.enumerated() {
                    (r as NSString).draw(at: NSPoint(x: hud.minX + 18, y: hud.minY + 140 + CGFloat(i) * 23), withAttributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.9)
                    ])
                }
            }
        }
    }

    static func savePNG(_ bytes: [UInt8], _ W: Int, _ H: Int, _ path: String) {
        let cs = CGColorSpaceCreateDeviceRGB()
        bytes.withUnsafeBytes { raw in
            guard let prov = CGDataProvider(data: Data(raw) as CFData),
                  let img = CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4,
                                    space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                                    provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                  let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dst, img, nil)
            CGImageDestinationFinalize(dst)
        }
    }
}

// MARK: - Entry Point & CLI

let args = Array(CommandLine.arguments.dropFirst())
if let idx = args.firstIndex(where: { ["--record-demo", "--record-interactions", "--record-weaves"].contains($0) }), idx + 1 < args.count {
    let outPath = args[idx + 1]
    let stills = args.firstIndex(of: "--stills").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    do { try DemoRecorder.run(outputPath: outPath, stillsDir: stills, interactionDemo: args[idx] == "--record-interactions", weaveDemo: args[idx] == "--record-weaves"); exit(0) }
    catch { fputs("Demo recorder failed: \(error)\n", stderr); exit(1) }
}
if args.contains("--help") || args.contains("-h") {
    print("""
    NotchBanner — Giant 4K Velvet Theater Curtain for the macOS Notch

    Usage:
      NotchBanner                         Launch menu-bar app (⌃⌥⌘B to toggle)
      NotchBanner --board <file.json>     Show a live 4K info board from JSON
      NotchBanner --text "Title\\nLine 2"  Show quick text on the 4K velvet board
      NotchBanner --record-demo out.mp4 [--stills dir]   Render 1080p60 Metal demo
    """)
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
if let i = args.firstIndex(of: "--board"), i + 1 < args.count {
    BannerBoard.customBoardURL = URL(fileURLWithPath: args[i + 1])
    delegate.startWithBoard = true
}
if let i = args.firstIndex(of: "--text"), i + 1 < args.count {
    BannerBoard.inlineText = args[i + 1].replacingOccurrences(of: "\\n", with: "\n")
    delegate.startWithBoard = true
}
app.delegate = delegate
app.run()
