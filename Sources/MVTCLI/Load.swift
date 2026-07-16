import ArgumentParser
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GISTools
import MVTTools

extension CLI {

    /// A command that downloads all tiles within a bounding box from a
    /// templated tile URL template into a local directory.
    ///
    /// The tile URL template must contain `{z}`, `{x}`, and `{y}` placeholders
    /// (case-insensitive) which are substituted with the resolved zoom level
    /// and each tile's coordinates. Alternatively, the URL may contain a
    /// literal numeric zoom segment (e.g. `.../14/{x}/{y}.pbf`); the first
    /// such segment is used and `--zoom` overrides it.
    struct Load: AsyncParsableCommand {

        static let configuration = CommandConfiguration(
            commandName: "load",
            abstract: "Download all tiles within a bounding box from a tile URL template",
            discussion: """
            The base URL must contain {z}, {x}, and {y} placeholders (case-insensitive) \
            that are substituted with each tile's coordinates. If the URL also contains \
            a literal numeric zoom segment (e.g. .../14/{x}/{y}.pbf), that zoom level \
            is inferred; otherwise --zoom is required.

            The bounding box is specified as 'minLon,minLat,maxLon,maxLat' in WGS84 \
            degrees. Tiles are enumerated with a tile-cover algorithm which walks the \
            bounding box edges in tile space and handles antimeridian crossing.

            Examples:
              mvt load --bbox "11.0,3.0,12.0,4.0" --output-dir ./tiles \\
                  https://example.com/tiles/14/{x}/{y}.pbf
              mvt load --bbox "11.0,3.0,12.0,4.0" --output-dir ./tiles --layout tree \\
                  --zoom 12 https://example.com/tiles/{z}/{x}/{y}.pbf
            """)

        @Option(
            name: [.short, .customLong("bbox")],
            help: "Bounding box as 'minLon,minLat,maxLon,maxLat' in WGS84 degrees.")
        var boundingBox: String

        @Option(
            name: [.short, .customLong("output-dir")],
            help: "Directory where tiles are written. Created if it does not exist.",
            completion: .directory)
        var outputDirectory: String

        @Option(
            name: [.short, .customLong("zoom")],
            help: "Zoom level. Required when the URL has no literal numeric z segment.")
        var zoom: Int?

        @Option(
            name: .customLong("layout"),
            help: "Output layout: 'flat' (default, z_x_y.ext) or 'tree' (z/x/y.ext).")
        var layout: LoadLayout = .flat

        @Flag(
            name: .customLong("overwrite-existing"),
            help: "Overwrite tiles that already exist in the output directory.")
        var overwriteExisting = false

        @Option(
            name: .customLong("concurrency"),
            help: "Maximum number of concurrent downloads (default: 8).")
        var concurrency: Int = 8

        @OptionGroup
        var options: Options

        @Argument(
            help: "Tile URL template containing {z}/{x}/{y} placeholders.")
        var baseURL: String

        mutating func run() async throws {
            try await Self.run(
                boundingBox: boundingBox,
                outputDirectory: outputDirectory,
                zoom: zoom,
                layout: layout,
                overwriteExisting: overwriteExisting,
                concurrency: concurrency,
                baseURL: baseURL,
                verbose: options.verbose)
        }

        // MARK: - Execution

        /// Shared execution entry point for ``CLI.Load``.
        ///
        /// Split out from `run()` so tests and aliases can invoke the logic
        /// without going through `ArgumentParser`.
        static func run(
            boundingBox: String,
            outputDirectory: String,
            zoom: Int?,
            layout: LoadLayout,
            overwriteExisting: Bool,
            concurrency: Int,
            baseURL: String,
            verbose: Bool
        ) async throws {
            // 1. Parse the bounding box
            let bbox = try parseBoundingBox(boundingBox)

            // 2. Resolve the zoom level from the URL or --zoom
            let resolvedZoom = try resolveZoom(from: baseURL, fallback: zoom)

            // 3. Validate the URL template contains the needed placeholders
            let template = baseURL
            let hasXPlaceholder = template.range(of: "{x}", options: .caseInsensitive) != nil
            let hasYPlaceholder = template.range(of: "{y}", options: .caseInsensitive) != nil
            guard hasXPlaceholder, hasYPlaceholder else {
                throw CLIError("The base URL must contain {x} and {y} placeholders (got '\(template)').")
            }

            // 4. Determine the file extension from the URL template
            let templateURL = URL(string: template) ?? URL(fileURLWithPath: template)
            let fileExtension = templateURL.pathExtension.isEmpty
                ? "pbf"
                : templateURL.pathExtension

            // 5. Prepare the output directory
            let outputURL = URL(fileURLWithPath: outputDirectory)
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: true)

            // 6. Enumerate tiles via the GISTools tile-cover algorithm
            let tiles = bbox.tileCover(atZoom: resolvedZoom)
            if tiles.isEmpty {
                if verbose {
                    print("No tiles cover the given bounding box at zoom \(resolvedZoom).")
                }
                print("Loaded 0 tiles into \(outputURL.path)")
                return
            }

            // 7. Concurrency control
            let maxConcurrent = max(1, concurrency)
            let semaphore = AsyncSemaphore(maxConcurrent)

            // 8. Download all tiles concurrently
            let total = tiles.count
            let counter = DownloadCounter(total: total)

            await withTaskGroup(of: Void.self) { group in
                for tile in tiles {
                    group.addTask {
                        await semaphore.wait()
                        defer { Task { await semaphore.signal() } }

                        await Self.downloadTile(
                            tile,
                            zoom: resolvedZoom,
                            template: template,
                            layout: layout,
                            fileExtension: fileExtension,
                            outputURL: outputURL,
                            overwriteExisting: overwriteExisting,
                            verbose: verbose,
                            counter: counter)
                    }
                }
            }

            // 9. Final summary
            let (downloaded, skipped, failed) = await counter.results()
            if verbose {
                // Clear the progress line and print the final summary to stderr
                FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
                let summary = "Loaded \(downloaded) tiles (\(skipped) skipped, \(failed) failed) into \(outputURL.path)\n"
                FileHandle.standardError.write(Data(summary.utf8))
            }
            else {
                print("Loaded \(downloaded) tiles (\(skipped) skipped, \(failed) failed) into \(outputURL.path)")
            }
        }

        // MARK: - Tile download

        /// Downloads a single tile and writes it to disk, updating progress.
        ///
        /// Soft failures (HTTP non-2xx, network errors, missing files) are
        /// silently skipped when `verbose` is false, and logged to stderr
        /// when `verbose` is true.
        private static func downloadTile(
            _ tile: MapTile,
            zoom: Int,
            template: String,
            layout: LoadLayout,
            fileExtension: String,
            outputURL: URL,
            overwriteExisting: Bool,
            verbose: Bool,
            counter: DownloadCounter
        ) async {
            // Build the final URL by substituting placeholders
            let urlString = template
                .replacingOccurrences(of: "{z}", with: "\(zoom)", options: .caseInsensitive)
                .replacingOccurrences(of: "{x}", with: "\(tile.x)", options: .caseInsensitive)
                .replacingOccurrences(of: "{y}", with: "\(tile.y)", options: .caseInsensitive)

            // `URL(string:)` rejects the `{`/`}` characters that appear in
            // templated paths, and also percent-encodes `{x}` style
            // placeholders before substitution. After substitution the URL
            // should be well-formed for http(s) — but for file paths we must
            // use `URL(fileURLWithPath:)` to avoid escaping issues.
            let url: URL
            if urlString.hasPrefix("file://") {
                // Strip the scheme, build a file URL, re-add nothing —
                // `URL(fileURLWithPath:)` produces a proper file:// URL.
                let path = String(urlString.dropFirst("file://".count))
                url = URL(fileURLWithPath: path)
            }
            else if urlString.hasPrefix("http://")
                        || urlString.hasPrefix("https://")
            {
                guard let parsed = URL(string: urlString) else {
                    await counter.recordFailure()
                    await Self.printProgress(counter: counter, verbose: verbose, message: "Invalid URL: \(urlString)")
                    return
                }
                url = parsed
            }
            else {
                // Treat anything else as a local file path
                url = URL(fileURLWithPath: urlString)
            }

            // Compute the destination path
            let destination = layout.destinationURL(
                for: tile,
                zoom: zoom,
                fileExtension: fileExtension,
                in: outputURL)

            // Skip existing unless overwrite is requested
            if FileManager.default.fileExists(atPath: destination.path) {
                if overwriteExisting {
                    // proceed to download and overwrite
                }
                else {
                    await counter.recordSkipped()
                    await Self.printProgress(counter: counter, verbose: verbose, message: "Skipped existing: \(destination.lastPathComponent)")
                    return
                }
            }

            // Create parent directories for tree layout
            let parent = destination.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

            // Download
            do {
                let data: Data
                let statusOK: Bool
                let statusCode: Int

                if url.isFileURL {
                    // Direct file read — `URLSession` does not support the
                    // `file://` scheme on all platforms (notably Linux).
                    data = try Data(contentsOf: url)
                    statusOK = true
                    statusCode = 200
                }
                else {
                    let (responseData, response) = try await URLSession.shared.data(from: url)
                    data = responseData
                    if let http = response as? HTTPURLResponse {
                        statusCode = http.statusCode
                        statusOK = (200 ..< 300).contains(http.statusCode)
                    }
                    else {
                        statusCode = 200
                        statusOK = true
                    }
                }

                guard statusOK else {
                    await counter.recordFailure()
                    await Self.printProgress(counter: counter, verbose: verbose, message: "Failed (\(statusCode)): \(url.lastPathComponent)")
                    return
                }

                try data.write(to: destination, options: .atomic)
                await counter.recordDownloaded()
                await Self.printProgress(counter: counter, verbose: verbose, message: nil)
            }
            catch {
                await counter.recordFailure()
                await Self.printProgress(counter: counter, verbose: verbose, message: "Failed (\(error.localizedDescription)): \(url.lastPathComponent)")
            }
        }

        /// Prints a progress line to stderr (when verbose) using a carriage
        /// return to overwrite the previous line. The line shows the
        /// completion count, percentage, elapsed runtime, and ETA. If
        /// `message` is non-nil it is appended as a short status note.
        private static func printProgress(
            counter: DownloadCounter,
            verbose: Bool,
            message: String?
        ) async {
            guard verbose else { return }
            let snapshot = await counter.snapshot()

            var line = "\rLoading tiles: \(snapshot.completed)/\(snapshot.total) (\(snapshot.percent)%)"
            line += " [\(formatDuration(snapshot.elapsedSeconds))]"
            if let remaining = snapshot.remainingSeconds {
                line += " eta \(formatDuration(remaining))"
            }
            if snapshot.skipped > 0 || snapshot.failed > 0 {
                var parts: [String] = []
                if snapshot.skipped > 0 { parts.append("\(snapshot.skipped) skipped") }
                if snapshot.failed > 0 { parts.append("\(snapshot.failed) failed") }
                line += " (" + parts.joined(separator: ", ") + ")"
            }
            if let message {
                line += " — \(message)"
            }
            // Pad to overwrite the longest line written so far. Measure the
            // visible content length (without the leading `\r`).
            let visibleLength = line.count - 1
            let padding = await counter.paddingForLine(lineLength: visibleLength)
            line += String(repeating: " ", count: padding)
            FileHandle.standardError.write(Data(line.utf8))
        }

        /// Formats a duration in seconds as a compact human-readable string
        /// (e.g. `0:05`, `1:23`, `12:04`). Hours are shown only when the
        /// duration exceeds one hour.
        /// - Parameter seconds: The duration in seconds.
        /// - Returns: A formatted string like `M:SS` or `H:MM:SS`.
        private static func formatDuration(_ seconds: Int) -> String {
            let hours = seconds / 3_600
            let minutes = (seconds % 3_600) / 60
            let secs = seconds % 60
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, secs)
            }
            else {
                return String(format: "%d:%02d", minutes, secs)
            }
        }

        // MARK: - Parsing helpers

        /// Parses a comma-separated `minLon,minLat,maxLon,maxLat` string in
        /// WGS84 degrees into a `BoundingBox`.
        ///
        /// Coordinates are strictly validated to be within their valid ranges
        /// (`longitude` in `-180.0 ... 180.0`, `latitude` in `-90.0 ... 90.0`),
        /// and `minLon <= maxLon` and `minLat <= maxLat` is enforced.
        ///
        /// - Parameter rawValue: The raw bounding box string.
        /// - Returns: A `BoundingBox` covering the requested region.
        /// - Throws: `CLIError` if the string is malformed or out of range.
        private static func parseBoundingBox(_ rawValue: String) throws -> BoundingBox {
            let parts = rawValue.components(separatedBy: ",")
            guard parts.count == 4 else {
                throw CLIError("Bounding box must be 'minLon,minLat,maxLon,maxLat' (got '\(rawValue)').")
            }

            guard let minLon = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let minLat = Double(parts[1].trimmingCharacters(in: .whitespaces)),
                  let maxLon = Double(parts[2].trimmingCharacters(in: .whitespaces)),
                  let maxLat = Double(parts[3].trimmingCharacters(in: .whitespaces))
            else {
                throw CLIError("Bounding box values must be numeric (got '\(rawValue)').")
            }

            guard minLon >= -180.0, maxLon <= 180.0 else {
                throw CLIError("Longitude must be in -180.0 ... 180.0 (got \(minLon) ... \(maxLon)).")
            }
            guard minLat >= -90.0, maxLat <= 90.0 else {
                throw CLIError("Latitude must be in -90.0 ... 90.0 (got \(minLat) ... \(maxLat)).")
            }
            guard minLon <= maxLon else {
                throw CLIError("minLon (\(minLon)) must be <= maxLon (\(maxLon)).")
            }
            guard minLat <= maxLat else {
                throw CLIError("minLat (\(minLat)) must be <= maxLat (\(maxLat)).")
            }

            return BoundingBox(
                southWest: Coordinate3D(latitude: minLat, longitude: minLon),
                northEast: Coordinate3D(latitude: maxLat, longitude: maxLon))
        }

        /// Resolves the zoom level by parsing a literal numeric segment from
        /// the URL path, falling back to the `--zoom` option when none is
        /// found.
        ///
        /// Two forms are recognised:
        ///   1. A standalone numeric path segment (e.g. `.../14/{x}/{y}.pbf`).
        ///   2. A segment that starts with a numeric prefix followed by
        ///      placeholders or other characters (e.g. `14_{x}_{y}.pbf`).
        ///
        /// Placeholder segments like `{x}`, `{y}`, `{z}` are skipped. The
        /// first matching segment with a value in `0 ... 30` is used.
        ///
        /// - Parameters:
        ///   - urlString: The tile URL template.
        ///   - fallback: An optional `--zoom` value.
        /// - Returns: The resolved zoom level.
        /// - Throws: `CLIError` if the zoom level cannot be determined.
        private static func resolveZoom(
            from urlString: String,
            fallback: Int?
        ) throws -> Int {
            // Try to find a literal numeric path segment, ignoring placeholders
            if let url = URL(string: urlString) ?? URL(string: "file://" + urlString) {
                let pathComponents = url.pathComponents.filter { component in
                    !component.isEmpty
                        && component != "/"
                        && component.lowercased() != "{z}"
                        && component.lowercased() != "{x}"
                        && component.lowercased() != "{y}"
                }
                for component in pathComponents {
                    // Strip a trailing extension like "14.pbf"
                    let candidate = component.split(separator: ".").first.map(String.init) ?? component

                    // Form 1: pure integer
                    if let z = Int(candidate), z >= 0, z <= 30 {
                        return z
                    }

                    // Form 2: leading numeric prefix like "14_{x}_{y}"
                    let leadingDigits = String(candidate.prefix { $0.isWholeNumber })
                    if let z = Int(leadingDigits), !leadingDigits.isEmpty, z >= 0, z <= 30 {
                        return z
                    }
                }
            }

            // Fall back to --zoom
            guard let z = fallback else {
                throw CLIError("Could not infer zoom level from the URL; please specify --zoom.")
            }
            guard z >= 0, z <= 30 else {
                throw CLIError("Zoom level must be in 0 ... 30 (got \(z)).")
            }
            return z
        }

    }

    // MARK: - LoadLayout

    /// The output directory layout for downloaded tiles.
    enum LoadLayout: String, CaseIterable, ExpressibleByArgument {

        /// All tiles in a single directory, named `z_x_y.ext`.
        case flat

        /// Slippy map directory hierarchy: `z/x/y.ext`.
        case tree

        // MARK: ExpressibleByArgument

        init?(argument: String) {
            self.init(rawValue: argument.lowercased())
        }

        /// Builds the destination `URL` for a tile under the given output
        /// directory, using the receiver's layout convention.
        ///
        /// - Parameters:
        ///   - tile: The map tile to locate.
        ///   - zoom: The resolved zoom level.
        ///   - fileExtension: The file extension (without leading dot).
        ///   - outputURL: The output directory URL.
        /// - Returns: The absolute file URL for the tile.
        func destinationURL(
            for tile: MapTile,
            zoom: Int,
            fileExtension: String,
            in outputURL: URL
        ) -> URL {
            switch self {
            case .flat:
                return outputURL
                    .appendingPathComponent("\(zoom)_\(tile.x)_\(tile.y).\(fileExtension)")

            case .tree:
                return outputURL
                    .appendingPathComponent("\(zoom)")
                    .appendingPathComponent("\(tile.x)")
                    .appendingPathComponent("\(tile.y).\(fileExtension)")
            }
        }

    }

    // MARK: - AsyncSemaphore

    /// A simple async-compatible counting semaphore for throttling
    /// concurrent tasks within a `TaskGroup`.
    ///
    /// `wait()` suspends until a permit is available; `signal()` releases
    /// one permit. Permits are fair (FIFO) under contention.
    actor AsyncSemaphore {

        private let capacity: Int
        private var available: Int
        private var pending: [CheckedContinuation<Void, Never>] = []

        /// Creates a semaphore with the given number of initial permits.
        /// - Parameter capacity: The maximum number of concurrent permits.
        init(_ capacity: Int) {
            self.capacity = capacity
            self.available = capacity
        }

        /// Waits for a permit, suspending the caller if none is available.
        func wait() async {
            if available > 0 {
                available -= 1
                return
            }
            await withCheckedContinuation { continuation in
                pending.append(continuation)
            }
        }

        /// Releases a permit, resuming a waiting caller if one exists.
        func signal() {
            if let continuation = pending.first {
                pending.removeFirst()
                continuation.resume()
            }
            else if available < capacity {
                available += 1
            }
        }

    }

    // MARK: - DownloadCounter

    /// Tracks download progress counters shared across concurrent tasks.
    actor DownloadCounter {

        private let total: Int
        private let startTime: ContinuousClock.Instant
        private var downloaded = 0
        private var skipped = 0
        private var failed = 0

        /// The character count of the longest progress line written so far.
        /// Used to pad subsequent shorter lines so they fully overwrite the
        /// previous content on the terminal.
        private var maxLineLength = 0

        /// Creates a counter for the given total number of tiles.
        /// - Parameter total: The total number of tiles to download.
        init(total: Int) {
            self.total = total
            self.startTime = .now
        }

        /// Records a successful download.
        func recordDownloaded() { downloaded += 1 }

        /// Records a skipped tile (already existed).
        func recordSkipped() { skipped += 1 }

        /// Records a failed download (HTTP error, network error, ...).
        func recordFailure() { failed += 1 }

        /// Returns the final counters as a tuple.
        /// - Returns: `(downloaded, skipped, failed)`.
        func results() -> (downloaded: Int, skipped: Int, failed: Int) {
            (downloaded, skipped, failed)
        }

        /// Records the length of a progress line and returns the padding
        /// width needed to overwrite the longest line written so far.
        ///
        /// Callers build the visible line content (without the leading
        /// `\r` or trailing padding), pass its length here, and receive
        /// the number of spaces to append so the rendered line is at
        /// least `maxLineLength` characters wide.
        ///
        /// - Parameter lineLength: The length of the line about to be written.
        /// - Returns: The number of padding spaces to append.
        func paddingForLine(lineLength: Int) -> Int {
            let padding = max(0, maxLineLength - lineLength)
            if lineLength > maxLineLength {
                maxLineLength = lineLength
            }
            return padding
        }

        /// Returns a snapshot of the progress for display, including the
        /// elapsed time and an estimated time to completion.
        ///
        /// The ETA is computed from the completion rate (`completed / elapsed`)
        /// and the remaining tiles. When no tiles have completed yet, the
        /// ETA is `nil`.
        ///
        /// - Returns: A snapshot with counters, total, elapsed seconds, and
        ///   optional remaining seconds.
        func snapshot() -> ProgressSnapshot {
            let completed = downloaded + skipped + failed
            let elapsed = startTime.duration(to: .now)
            let elapsedSeconds = Int(elapsed.components.seconds)
            let remainingSeconds: Int?
            if completed > 0, completed < total {
                let perTile = Double(elapsedSeconds) / Double(completed)
                let remaining = Double(total - completed) * perTile
                remainingSeconds = Int(remaining.rounded())
            }
            else {
                remainingSeconds = nil
            }
            return ProgressSnapshot(
                downloaded: downloaded,
                skipped: skipped,
                failed: failed,
                total: total,
                elapsedSeconds: elapsedSeconds,
                remainingSeconds: remainingSeconds)
        }

    }

    /// An immutable snapshot of download progress for display.
    struct ProgressSnapshot: Sendable {

        let downloaded: Int
        let skipped: Int
        let failed: Int
        let total: Int
        let elapsedSeconds: Int
        let remainingSeconds: Int?

        /// The number of completed tiles (downloaded, skipped, or failed).
        var completed: Int { downloaded + skipped + failed }

        /// The completion percentage as an integer 0...100.
        var percent: Int {
            guard total > 0 else { return 0 }
            return Int((Double(completed) / Double(total) * 100.0).rounded())
        }

    }

}
