import Foundation
import AppKit

class AudioProcessor: ObservableObject {
    @Published var isProcessing = false
    @Published var processedCount = 0
    @Published var totalCount = 0
    @Published var currentStatus = ""
    
    private let ramenFolderURL: URL
    private var autoAddFolderURL: URL? {
        let fileManager = FileManager.default
        let musicURL = fileManager.urls(for: .musicDirectory, in: .userDomainMask).first!
        let possiblePaths = [
            "Music/Media.localized/Automatically Add to Music.localized",
            "Music/Media/Automatically Add to Music",
            "iTunes/iTunes Media/Automatically Add to Music",
            "iTunes/iTunes Media.localized/Automatically Add to Music.localized"
        ]
        
        for path in possiblePaths {
            let folderURL = musicURL.appendingPathComponent(path)
            if fileManager.fileExists(atPath: folderURL.path) {
                return folderURL
            }
        }
        return nil
    }
    
    private var destinationDirectoryURL: URL {
        let isQuickConvert = UserDefaults.standard.bool(forKey: "quickConvertEnabled")
        if isQuickConvert {
            let customPath = UserDefaults.standard.string(forKey: "customDestinationPath") ?? ""
            if !customPath.isEmpty, FileManager.default.fileExists(atPath: customPath) {
                return URL(fileURLWithPath: customPath)
            } else {
                let defaultQuickPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appendingPathComponent("ramen-quick-convert")
                try? FileManager.default.createDirectory(at: defaultQuickPath, withIntermediateDirectories: true, attributes: nil)
                return defaultQuickPath
            }
        } else {
            return ramenFolderURL
        }
    }
    
    init() {
        let fileManager = FileManager.default
        let musicURL = fileManager.urls(for: .musicDirectory, in: .userDomainMask).first!
        self.ramenFolderURL = musicURL.appendingPathComponent("Ramen")
        
        // Ensure Ramen directory exists
        if !fileManager.fileExists(atPath: ramenFolderURL.path) {
            do {
                try fileManager.createDirectory(at: ramenFolderURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create Ramen folder: \(error)")
            }
        }
    }
    
    func processFiles(_ urls: [URL]) {
        self.totalCount = urls.count
        self.processedCount = 0
        self.isProcessing = true
        self.currentStatus = "Initializing conversion..."
        
        let autoAddFolder = self.autoAddFolderURL
        let isQuickConvert = UserDefaults.standard.bool(forKey: "quickConvertEnabled")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let group = DispatchGroup()
            let counterQueue = DispatchQueue(label: "com.harperquigley.ramen.counter")
            var completed = 0
            var finalURLsToImport: [URL] = []
            
            // Execute in fully parallel batches to max out CPU cores and speed
            DispatchQueue.concurrentPerform(iterations: urls.count) { index in
                let url = urls[index]
                let fileName = url.lastPathComponent
                
                group.enter()
                self.processSingleFile(url) { finalFileURL in
                    if let finalURL = finalFileURL {
                        // Queue up successful ffmpeg output to the import array atomically
                        counterQueue.sync { finalURLsToImport.append(finalURL) }
                    }
                    
                    counterQueue.sync {
                        completed += 1
                        let currentCount = completed
                        DispatchQueue.main.async {
                            self.currentStatus = "Processed \(fileName)..."
                            self.processedCount = currentCount
                        }
                    }
                    group.leave()
                }
            }
            
            group.wait()
            
            DispatchQueue.main.async {
                self.currentStatus = isQuickConvert ? "Gathering exported files..." : "Importing into Music library..."
            }
            
            // Sort to ensure track order is somewhat respected during iterative adds
            finalURLsToImport.sort(by: { $0.lastPathComponent < $1.lastPathComponent })
            
            if !isQuickConvert {
                // Sequence into the active Music folder dynamically to flawlessly trigger Music imports without auto-playing
                if let addFolder = autoAddFolder {
                    for urlToImport in finalURLsToImport {
                        let dropURL = addFolder.appendingPathComponent(urlToImport.lastPathComponent)
                        do {
                            if FileManager.default.fileExists(atPath: dropURL.path) {
                                try FileManager.default.removeItem(at: dropURL)
                            }
                            try FileManager.default.copyItem(at: urlToImport, to: dropURL)
                        } catch {
                            print("Failed to copy to auto-add folder: \(error)")
                        }
                        Thread.sleep(forTimeInterval: 0.15) // small 150ms stagger per track lets Music reliably process tags cleanly
                    }
                } else {
                    for urlToImport in finalURLsToImport {
                        NSWorkspace.shared.open([urlToImport], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Music.app"), configuration: NSWorkspace.OpenConfiguration())
                        Thread.sleep(forTimeInterval: 0.15)
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.currentStatus = "Done!"
            }
            
            // Allow UI to show success state briefly
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.isProcessing = false
                self.totalCount = 0
                self.processedCount = 0
                self.currentStatus = ""
                
                if isQuickConvert, let firstURL = finalURLsToImport.first {
                    NSWorkspace.shared.activateFileViewerSelecting([firstURL])
                }
            }
        }
    }
    
    private func processSingleFile(_ inputURL: URL, completion: @escaping (URL?) -> Void) {
        let fileExtension = inputURL.pathExtension.lowercased()
        let fileName = inputURL.deletingPathExtension().lastPathComponent
        
        // Find destination location based on dynamic setting state
        let currentTargetDir = destinationDirectoryURL
        
        let bypassFormats = ["mp3", "m4a", "aac", "alac"]
        if bypassFormats.contains(fileExtension) {
            // Directly link/copy pre-encoded formats
            let outputURL = currentTargetDir.appendingPathComponent("\(fileName).\(fileExtension)")
            copyFile(from: inputURL, to: outputURL)
            completion(outputURL)
        } else if fileExtension == "flac" || fileExtension == "wav" {
            // Convert to ALAC while explicitly retaining metadata using ffmpeg
            let outputURL = currentTargetDir.appendingPathComponent("\(fileName).m4a")
            convertFileToALAC(inputURL: inputURL, outputURL: outputURL) { success in
                completion(success ? outputURL : nil)
            }
        } else {
            // Unsupported format
            completion(nil)
        }
    }
    
    private func copyFile(from: URL, to: URL) {
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: to.path) {
                try fileManager.removeItem(at: to)
            }
            try fileManager.copyItem(at: from, to: to)
        } catch {
            print("Failed to copy file: \\(error)")
        }
    }
    
    private func convertFileToALAC(inputURL: URL, outputURL: URL, completion: @escaping (Bool) -> Void) {
        let task = Process()
        
        // Use internally bundled ffmpeg first, otherwise falback to possible local brew
        if let bundleFFMPEGRoute = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            task.executableURL = URL(fileURLWithPath: bundleFFMPEGRoute)
        } else {
            task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        }
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            do {
                try fileManager.removeItem(at: outputURL)
            } catch {
                print("Failed to remove existing file: \\(error)")
            }
        }
        
        // Advanced metadata mapping for iTunes / Apple Music compatibility in m4a.
        // -map 0 maps all input streams (audio and art data)
        // -c:a alac converts the audio.
        // -c:v copy preserves the image format embedded.
        // -map_metadata 0 forces the exact global tags from Flac into the MP4 container.
        // -write_id3v2 1 forces it into id3 for fallback
        task.arguments = ["-y", "-i", inputURL.path, "-map", "0", "-c:v", "copy", "-c:a", "alac", "-map_metadata", "0", "-write_id3v2", "1", outputURL.path]
        
        do {
            // Silence stdout/stderr from FFMPEG
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            try task.run()
            task.waitUntilExit()
            completion(task.terminationStatus == 0)
        } catch {
            print("ffmpeg failed to run: \\(error)")
            completion(false)
        }
    }
}
