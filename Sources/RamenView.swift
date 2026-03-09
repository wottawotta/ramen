import SwiftUI
import UniformTypeIdentifiers

struct RamenView: View {
    @StateObject private var processor = AudioProcessor()
    @State private var isTargeted = false
    @State private var isHovering = false
    @State private var isHoveringGear = false
    @State private var isSettingsExpanded = false
    
    @AppStorage("quickConvertEnabled") private var quickConvertEnabled = false
    @AppStorage("customDestinationPath") private var customDestinationPath = ""

    // Apple Music Red
    let amRed = Color(red: 250/255, green: 35/255, blue: 59/255)
    // Drag and Drop Green
    let dropGreen = Color(red: 52/255, green: 199/255, blue: 89/255)
    
    var body: some View {
        GeometryReader { proxy in
        HStack(spacing: 0) {
            // Main App View (Always 320x320)
            ZStack {
                // Outer Dashed Border Box
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(
                            lineWidth: isTargeted ? 4 : 3,
                            dash: [12, 10]
                        )
                    )
                    .foregroundColor(isTargeted ? dropGreen : Color.gray.opacity(0.3))
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(isTargeted ? dropGreen.opacity(0.05) : Color.clear)
                    )
                    .padding(20)
                    .animation(.easeInOut(duration: 0.2), value: isTargeted)
                
                VStack(spacing: 24) {
                    // Main Icon Area
                    if processor.isProcessing {
                        VStack(spacing: 12) {
                            Text("Processing \(processor.processedCount) of \(processor.totalCount)")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            // Clean Progress Bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                        .frame(width: 200, height: 6)
                                        .foregroundColor(Color.gray.opacity(0.2))
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .frame(width: 200 * CGFloat(Double(processor.processedCount) / Double(max(1, processor.totalCount))), height: 6)
                                        .foregroundColor(amRed)
                                        .animation(.spring(), value: processor.processedCount)
                                }
                            }
                            .frame(width: 200, height: 6)
                            
                            // Status String updates
                            Text(processor.currentStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .frame(width: 220)
                                .truncationMode(.middle)
                        }
                        
                    } else {
                        // Idle State (Clean Drag & Drop Box)
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(lineWidth: 3)
                                .foregroundColor(isTargeted ? dropGreen : Color.gray.opacity(0.5))
                                .frame(width: 72, height: 72)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(isHovering ? Color.gray.opacity(0.1) : Color.clear)
                                )
                            
                            Image(systemName: "plus")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(isTargeted ? dropGreen : Color.gray.opacity(0.8))
                        }
                        .scaleEffect(isHovering ? 1.05 : 1.0)
                        .scaleEffect(isTargeted ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTargeted)
                        
                        VStack(spacing: 6) {
                            Text("Drop your audio here")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("or click to select it in Finder")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                
                            Text("FLAC • WAV • MP3 • M4A")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.top, 4)
                        }
                    }
                }
                .onHover { hovering in
                    isHovering = hovering
                }
                .onTapGesture {
                    if !processor.isProcessing && !isSettingsExpanded {
                        openFileSelector()
                    }
                }
            }
            .frame(width: 320, height: 320)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Settings Slide-out Menu
            if isSettingsExpanded {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Settings")
                        .font(.headline)
                        .padding(.bottom, -4)
                    
                    Toggle(isOn: $quickConvertEnabled) {
                        Text("Quick Convert")
                            .fontWeight(.medium)
                    }
                    .toggleStyle(.switch)
                    .tint(amRed)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Destination Folder")
                            .font(.subheadline)
                            .foregroundColor(quickConvertEnabled ? .primary : .secondary)
                        
                        Button(action: selectCustomDestination) {
                            HStack {
                                Image(systemName: "folder")
                                Text(displayDestinationPath())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(!quickConvertEnabled)
                        .opacity(quickConvertEnabled ? 1.0 : 0.5)
                    }
                    
                    Text(quickConvertEnabled ? "Converts files to the selected folder and opens it when finished." : "Auto-add seamlessly adds converted files into Apple Music.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    
                    Spacer()
                }
                .padding(24)
                .frame(width: 240, height: 320)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.98))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        }
        .frame(width: isSettingsExpanded ? 560 : 320, height: 320, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSettingsExpanded)
        .overlay(alignment: .topTrailing) {
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isSettingsExpanded.toggle()
                }
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundColor(isSettingsExpanded || isHoveringGear ? .primary : .secondary)
                    .rotationEffect(Angle.degrees(isSettingsExpanded ? 90 : 0))
            }
            .buttonStyle(.plain)
            .padding(.top, -22)
            .padding(.trailing, 12)
            .onHover { hovering in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isHoveringGear = hovering
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            if processor.isProcessing { return false }
            
            var urls: [URL] = []
            let group = DispatchGroup()
            let lockQueue = DispatchQueue(label: "com.ramen.urlLock")
            
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                        if !isDir {
                            lockQueue.sync { urls.append(url) }
                        } else {
                            // Expand directory
                            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                                for case let fileURL as URL in enumerator {
                                    lockQueue.sync { urls.append(fileURL) }
                                }
                            }
                        }
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                let validURLs = urls.filter { url in
                    let ext = url.pathExtension.lowercased()
                    return ["flac", "wav", "mp3", "m4a", "aac", "alac"].contains(ext)
                }
                if !validURLs.isEmpty {
                    isSettingsExpanded = false
                    processor.processFiles(validURLs)
                }
            }
            return true
        }
    }
    
    private func displayDestinationPath() -> String {
        if customDestinationPath.isEmpty {
            return "ramen-quick-convert"
        } else {
            let url = URL(fileURLWithPath: customDestinationPath)
            return url.lastPathComponent
        }
    }
    
    private func selectCustomDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Output Folder"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                customDestinationPath = url.path
            }
        }
    }
    
    private func openFileSelector() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.audio, UTType.folder]
        
        if panel.runModal() == .OK {
            var urls: [URL] = []
            for url in panel.urls {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if !isDir {
                    urls.append(url)
                } else {
                    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                        for case let fileURL as URL in enumerator {
                            urls.append(fileURL)
                        }
                    }
                }
            }
            let validURLs = urls.filter { url in
                let ext = url.pathExtension.lowercased()
                return ["flac", "wav", "mp3", "m4a", "aac", "alac"].contains(ext)
            }
            if !validURLs.isEmpty {
                processor.processFiles(validURLs)
            }
        }
    }
}
