import CoreGraphics
import Foundation
import ImageIO
import Metal

/// Loads everything the coin renderer draws with: the meshes, the struck-relief atlas, the studio
/// environment, and the constants the shader reads.
///
/// All of it is exported by `coinage-viz` (`npm run export:native`) and vendored under
/// `CoinageAssets`. The constants arrive as data rather than as code, so a material tweak upstream
/// ships as a file change here.
final class CoinageAssetStore {
    struct Mesh {
        let positions: MTLBuffer
        let normals: MTLBuffer
        let surfaces: MTLBuffer
        let indices: MTLBuffer
        let indexCount: Int
    }

    enum Failure: Error {
        case missingAsset(String)
        case malformed(String)
        case deviceRefused(String)
    }

    let device: MTLDevice
    let params: Params
    let metalRows: [Float]
    let designs: [Design]
    let reliefAtlas: MTLTexture
    let environment: MTLTexture
    let environmentLevels: Int

    private let bundle: Bundle
    private let meshCatalogue: [String: [String: MeshEntry]]
    private let meshes: [String: Mesh]

    init(device: MTLDevice, bundle: Bundle = .main) throws {
        self.device = device
        self.bundle = bundle

        let manifest: Manifest = try Self.decode("manifest", in: bundle)
        let raw: RawParams = try Self.decode("params", in: bundle)
        let metals: [RawMetal] = try Self.decode("metals", in: bundle)
        let rawDesigns: [RawDesign] = try Self.decode("designs", in: bundle)
        let rawMeshes: [RawMesh] = try Self.decode("meshes", in: bundle)

        environmentLevels = manifest.env.cube.levels.count
        params = Params(raw: raw, levels: environmentLevels)
        metalRows = metals.flatMap { $0.reflectance + [$0.roughness] + $0.tone + [0] }
        designs = rawDesigns.map(Design.init(raw:))
        meshCatalogue = Dictionary(uniqueKeysWithValues: rawMeshes.map { ($0.id, $0.lods) })
        meshes = try meshCatalogue.reduce(into: [:]) { loaded, entry in
            for (lod, mesh) in entry.value {
                loaded["\(entry.key)-\(lod)"] = try Self.load(mesh, device: device, bundle: bundle)
            }
        }
        reliefAtlas = try Self.loadReliefAtlas(device: device, bundle: bundle)
        environment = try Self.loadEnvironment(
            device: device,
            bundle: bundle,
            levels: manifest.env.cube.levels
        )
    }

    /// Every mesh, already loaded. A lookup, never a read.
    ///
    /// They used to load on first use, which put a file read and four buffer allocations inside a
    /// draw. That is invisible while a coin keeps the same mesh and brutal when a field of them
    /// changes level of detail at once: coins fly out, the in-flight detail cap relaxes as they
    /// land, and two megabytes of high meshes are read in the middle of a frame. Every coin freezes
    /// for as long as it takes, including the ones already moving.
    ///
    /// All twenty-eight come to about three megabytes, which is cheaper to hold than to fetch at
    /// the wrong moment.
    func mesh(geometry: String, levelOfDetail: CoinageLevelOfDetail) throws -> Mesh {
        let key = "\(geometry)-\(Self.lodNames[levelOfDetail.rawValue])"

        guard let loaded = meshes[key] else { throw Failure.missingAsset("mesh \(key)") }

        return loaded
    }

    private static let lodNames = ["high", "mid", "low", "sliver"]
}

// MARK: - Shader constants

extension CoinageAssetStore {
    /// `CoinParams` in `CoinageCoin.metal`, field for field and in order. All floats, then one int,
    /// so it goes to the GPU as a flat buffer.
    struct Params {
        var viewportWidth: Float = 0
        var viewportHeight: Float = 0
        var dpr: Float = 2
        let tilePixels: Float
        let environmentMaxLod: Float
        var lightTurn: SIMD3<Float> = .zero
        let material: [Float]
        var backdrop: [Float] = [0, 0, 0]
        var debug: Int32 = 0

        fileprivate init(raw: RawParams, levels: Int) {
            tilePixels = raw.atlas.tilePx
            environmentMaxLod = Float(levels - 1)
            material = [
                raw.material.exposure, raw.material.luster, raw.material.rimLuster,
                raw.material.lusterMinPx, raw.material.studioRadius, raw.material.studioScale,
                raw.material.basin, raw.material.rollGloss, raw.material.rollReliefHaze,
                raw.native.envSharpen, raw.material.haze, raw.material.polish,
                raw.material.tone, raw.material.grime, raw.material.engraveDark,
                raw.material.frost, raw.material.wallRough, raw.material.aaVariance,
                raw.material.aaThreshold, raw.material.reliefBias
            ]
        }

        /// The struct's own alignment, from the `float2` it opens with.
        ///
        /// Metal rounds a struct's size up to its alignment, and on a device it refuses a bound
        /// buffer smaller than the argument the shader declares — it fails at the draw call, with
        /// nothing before it to say why. The simulator does not check, so the mismatch only shows
        /// on hardware. Padding to the same rule the shader uses keeps the two the same size
        /// however many fields are added.
        static let alignment = MemoryLayout<Float>.size * 2

        func packed() -> [Float] {
            var out: [Float] = [
                viewportWidth, viewportHeight, dpr, tilePixels, environmentMaxLod,
                lightTurn.x, lightTurn.y, lightTurn.z
            ]
            out += material
            out += backdrop
            out.append(Float(bitPattern: UInt32(bitPattern: debug)))

            let stride = Self.alignment / MemoryLayout<Float>.size
            out.append(contentsOf: Array(repeating: 0, count: out.count % stride))

            return out
        }
    }

    /// Only what the renderer needs off a design: our own banding decides metal and shape, so the
    /// reference's own choices are deliberately not read.
    struct Design {
        let thickness: Float
        let width: Float
        let reeds: Float
        let tile: Float

        fileprivate init(raw: RawDesign) {
            thickness = raw.thickness
            width = raw.width
            reeds = raw.reeds
            tile = Float(raw.tile)
        }
    }
}

// MARK: - Loading

private extension CoinageAssetStore {
    struct MeshEntry: Decodable {
        struct Array: Decodable {
            let offset: Int
            let count: Int
            let components: Int
        }

        let file: String
        let layout: [String: Array]
    }

    struct RawMesh: Decodable {
        let id: String
        let lods: [String: MeshEntry]
    }

    struct RawMetal: Decodable {
        /// Reflectance at normal incidence, `f0` in the exported file.
        let reflectance: [Float]
        let roughness: Float
        let tone: [Float]

        enum CodingKeys: String, CodingKey {
            case reflectance = "f0"
            case roughness
            case tone
        }
    }

    struct RawDesign: Decodable {
        let thickness: Float
        let width: Float
        let reeds: Float
        let tile: Int
    }

    struct RawParams: Decodable {
        struct Atlas: Decodable {
            let tilePx: Float
        }

        struct Native: Decodable {
            let envSharpen: Float
        }

        struct Material: Decodable {
            let exposure, luster, rimLuster, lusterMinPx, studioRadius, studioScale: Float
            let basin, rollGloss, rollReliefHaze, haze, polish, tone, grime: Float
            let engraveDark, frost, wallRough, aaVariance, aaThreshold, reliefBias: Float
        }

        let atlas: Atlas
        let native: Native
        let material: Material
    }

    struct Manifest: Decodable {
        struct Level: Decodable {
            let level: Int
            let size: Int
            let faces: [String: String]
        }

        struct Cube: Decodable {
            let levels: [Level]
        }

        struct Environment: Decodable {
            let cube: Cube
        }

        let env: Environment
    }

    static func decode<T: Decodable>(_ name: String, in bundle: Bundle) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw Failure.missingAsset("\(name).json")
        }

        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    static func load(_ entry: MeshEntry, device: MTLDevice, bundle: Bundle) throws -> Mesh {
        let name = (entry.file as NSString).lastPathComponent

        guard let url = bundle.url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: "bin"
        ) else {
            throw Failure.missingAsset(name)
        }

        let data = try Data(contentsOf: url)

        func buffer(_ key: String) throws -> (MTLBuffer, Int) {
            guard let array = entry.layout[key] else { throw Failure.malformed("layout \(key)") }

            let length = array.count * array.components * MemoryLayout<Float>.size

            guard array.offset + length <= data.count else {
                throw Failure.malformed("\(key) runs past the file")
            }

            let made: MTLBuffer? = data.withUnsafeBytes {
                device.makeBuffer(bytes: $0.baseAddress! + array.offset, length: length)
            }

            guard let made else { throw Failure.deviceRefused("mesh buffer \(key)") }

            return (made, array.count)
        }

        let indices = try buffer("index")

        return try Mesh(
            positions: buffer("position").0,
            normals: buffer("normal").0,
            surfaces: buffer("surf").0,
            indices: indices.0,
            indexCount: indices.1
        )
    }

    /// The normal map's RGB and the height map's red go into one RGBA8 texture.
    ///
    /// The atlas is generated for CASH rather than taken from the reference's currencies: every
    /// value is struck in the major unit with its decimals and no mark, so the fifteen faces read
    /// as one series. The reference's own atlases strike small values in the minor unit, which puts
    /// "16" and "0.16" on two coins of the same value.
    ///
    /// Both are read straight from the decoder with no colour management and no premultiplication:
    /// these are normals and heights, not colours, and either would corrupt them. They are vendored
    /// with a `.reliefpng` extension for the same reason, so Xcode's PNG compressor leaves them be.
    static func loadReliefAtlas(device: MTLDevice, bundle: Bundle) throws -> MTLTexture {
        let normal = try rawPixels("cash-normal", in: bundle)
        let height = try rawPixels("cash-height", in: bundle)

        guard normal.width == height.width, normal.height == height.height else {
            throw Failure.malformed("relief maps disagree on size")
        }

        var interleaved = [UInt8](repeating: 0, count: normal.width * normal.height * 4)

        for row in 0 ..< normal.height {
            for column in 0 ..< normal.width {
                let source = row * normal.bytesPerRow + column * normal.channels + normal.leadingAlpha
                let target = (row * normal.width + column) * 4

                interleaved[target] = normal.bytes[source]
                interleaved[target + 1] = normal.bytes[source + 1]
                interleaved[target + 2] = normal.bytes[source + 2]
                interleaved[target + 3] = height.bytes[
                    row * height.bytesPerRow + column * height.channels + height.leadingAlpha
                ]
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: normal.width,
            height: normal.height,
            mipmapped: true
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw Failure.deviceRefused("relief atlas")
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, normal.width, normal.height),
            mipmapLevel: 0,
            withBytes: interleaved,
            bytesPerRow: normal.width * 4
        )

        return texture
    }

    struct RawImage {
        let width: Int
        let height: Int
        let channels: Int
        let leadingAlpha: Int
        let bytesPerRow: Int
        let bytes: [UInt8]
    }

    static func rawPixels(_ name: String, in bundle: Bundle) throws -> RawImage {
        guard let url = bundle.url(forResource: name, withExtension: "reliefpng"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let data = image.dataProvider?.data as Data?
        else {
            throw Failure.missingAsset("\(name).reliefpng")
        }

        let alpha = image.alphaInfo
        let leading = alpha == .first || alpha == .noneSkipFirst || alpha == .premultipliedFirst

        return RawImage(
            width: image.width,
            height: image.height,
            channels: image.bitsPerPixel / 8,
            leadingAlpha: leading ? 1 : 0,
            bytesPerRow: image.bytesPerRow,
            bytes: [UInt8](data)
        )
    }

    /// Slices go in Metal's own face order; every level of the prefiltered chain is uploaded, so a
    /// rough metal reads a blurred studio without the shader doing the blurring.
    static func loadEnvironment(
        device: MTLDevice,
        bundle: Bundle,
        levels: [Manifest.Level]
    ) throws -> MTLTexture {
        guard let base = levels.first else { throw Failure.malformed("no environment levels") }

        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: .rgba16Float,
            size: base.size,
            mipmapped: true
        )
        descriptor.mipmapLevelCount = levels.count
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw Failure.deviceRefused("environment cube")
        }

        for level in levels {
            for (slice, face) in faceOrder.enumerated() {
                guard let path = level.faces[face] else {
                    throw Failure.malformed("level \(level.level) is missing \(face)")
                }

                let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension

                guard let url = bundle.url(forResource: name, withExtension: "hdr") else {
                    throw Failure.missingAsset("\(name).hdr")
                }

                let decoded = try CoinageRadianceImage.decode(Data(contentsOf: url))

                decoded.pixels.withUnsafeBytes { raw in
                    texture.replace(
                        region: MTLRegionMake2D(0, 0, decoded.width, decoded.height),
                        mipmapLevel: level.level,
                        slice: slice,
                        withBytes: raw.baseAddress!,
                        bytesPerRow: decoded.width * 8,
                        bytesPerImage: decoded.width * decoded.height * 8
                    )
                }
            }
        }

        return texture
    }

    static let faceOrder = ["px", "nx", "py", "ny", "pz", "nz"]
}
