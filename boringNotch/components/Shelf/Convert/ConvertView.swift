import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConvertTargetView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var converter = ConversionManager.shared
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 27, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(targeted ? .cyan : .white.opacity(0.7))
                .frame(width: 48, height: 48)
                .background(.white.opacity(targeted ? 0.14 : 0.07), in: Circle())
            Text("Convert")
                .font(.system(size: 13, weight: .semibold))
            Text("Drop files")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(targeted ? 0.12 : 0.055), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(targeted ? .cyan.opacity(0.8) : .white.opacity(0.11), lineWidth: 1.5)
        }
        .scaleEffect(targeted ? 1.035 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: targeted)
        .onChange(of: targeted) { _, value in vm.convertDropTargeting = value }
        .onDisappear { vm.convertDropTargeting = false }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard !providers.isEmpty else { return false }
            vm.dropEvent = true
            converter.prepare(providers: providers)
            return true
        }
        .accessibilityLabel("Convert files")
        .help("Drop files here to choose a conversion format")
    }
}

struct ConvertPanelView: View {
    @ObservedObject private var converter = ConversionManager.shared
    @ObservedObject private var preferences = ConversionPreferences.shared
    @State private var choosingFormat = false
    @State private var showingSettings = false
    @State private var search = ""
    @State private var showDetails = false

    private var selected: ConversionFormat? { converter.selectedFormat }
    private var first: ConversionInput? { converter.categoryInputs.first }
    private var filteredFormats: [ConversionFormat] {
        converter.formats.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                || $0.detail.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Group {
            switch converter.stage {
            case .idle: EmptyView()
            case .preparing: loadingView
            case .setup:
                if choosingFormat { formatPicker }
                else if showingSettings { settingsView }
                else { setupView }
            case .running: progressView
            case .finished: resultView
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover(perform: converter.hoverChanged)
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        .animation(.smooth(duration: 0.26), value: converter.stage)
    }

    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Checking files…").font(.system(size: 14, weight: .medium))
            Spacer()
            Button("Cancel") { converter.close() }
        }
        .padding(.top, 42)
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: first.map { NSWorkspace.shared.icon(forFile: $0.url.path) } ?? NSImage())
                    .resizable().scaledToFit().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(converter.categoryInputs.count == 1 ? first?.name ?? "Convert file" :
                            "\(converter.categoryInputs.count) files to convert")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Text(first?.isDirectory == true ? "Folder · ZIP archive available" :
                            "\(first?.displayType ?? "File") · \(ByteCountFormatter.string(fromByteCount: converter.totalSize, countStyle: .file))")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.57))
                }
                Spacer(minLength: 8)
                if converter.availableCategories.count > 1 {
                    Menu {
                        ForEach(converter.availableCategories) { category in
                            Button(category.rawValue) { converter.selectCategory(category) }
                        }
                    } label: {
                        Label(converter.selectedCategory.rawValue, systemImage: "square.stack")
                    }
                    .font(.system(size: 11))
                }
                Button { converter.close() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .help("Cancel")
            }

            HStack(spacing: 10) {
                Text("Convert to")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                Button {
                    search = ""
                    withAnimation(.snappy(duration: 0.22)) { choosingFormat = true }
                } label: {
                    HStack {
                        Text(selected?.name ?? "No compatible formats")
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .disabled(converter.formats.isEmpty)
                Button {
                    withAnimation(.snappy(duration: 0.22)) { showingSettings = true }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .help("Conversion settings")
            }
            if let note = converter.message {
                Text(note).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
            } else if let selected {
                Text(selected.detail + (converter.selectedCategory == .document || converter.selectedCategory == .archive
                                        ? "" : " · " + converter.preset.rawValue))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.52)).lineLimit(1)
            }
            HStack {
                Spacer()
                Button("Cancel") { converter.close() }
                    .foregroundStyle(.white.opacity(0.7))
                Button {
                    converter.start()
                } label: {
                    Label(converter.categoryInputs.count > 1 ? "Convert all" : "Convert", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background(.cyan, in: Capsule())
                        .foregroundStyle(.black)
                }
                .disabled(selected == nil)
            }
        }
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Choose a format").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Back") { withAnimation(.snappy(duration: 0.22)) { choosingFormat = false } }
            }
            TextField("Search formats", text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredFormats) { format in
                        Button {
                            converter.selectedFormatID = format.id
                            withAnimation(.snappy(duration: 0.22)) { choosingFormat = false }
                        } label: {
                            HStack {
                                Text(format.name).font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text(format.detail).font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .padding(.horizontal, 9).frame(height: 26)
                            .background(.white.opacity(format.id == converter.selectedFormatID ? 0.13 : 0.05),
                                        in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            }
            .frame(maxHeight: 86)
        }
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Conversion settings").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") { withAnimation(.snappy(duration: 0.22)) { showingSettings = false } }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Save to").foregroundStyle(.white.opacity(0.62))
                        Spacer()
                        Menu {
                            Button("Beside original") { preferences.useOriginalFolder() }
                            Button("Choose folder…") { preferences.chooseFolder() }
                        } label: {
                            Text(preferences.folderName).lineLimit(1)
                        }
                    }
                    HStack {
                        Text("Filename").foregroundStyle(.white.opacity(0.62))
                        Spacer()
                        Picker("Filename", selection: $preferences.naming) {
                            ForEach(ConversionPreferences.Naming.allCases) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }
                        .labelsHidden().frame(width: 160)
                    }
                    HStack {
                        Text("If name exists").foregroundStyle(.white.opacity(0.62))
                        Spacer()
                        Picker("If name exists", selection: $preferences.collision) {
                            ForEach(ConversionCollision.allCases) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }
                        .labelsHidden().frame(width: 160)
                    }
                    if converter.selectedCategory == .image || converter.selectedCategory == .video ||
                        converter.selectedCategory == .audio {
                        HStack {
                            Text("Quality").foregroundStyle(.white.opacity(0.62))
                            Spacer()
                            Picker("Quality", selection: $converter.preset) {
                                ForEach(ConversionPreset.allCases) { choice in
                                    Text(choice.rawValue).tag(choice)
                                }
                            }
                            .labelsHidden().frame(width: 160)
                        }
                    }
                    Toggle("Preserve metadata", isOn: $preferences.preserveMetadata)
                        .toggleStyle(.switch)
                }
            }
            .scrollIndicators(.hidden)
        }
        .font(.system(size: 11))
        .frame(maxWidth: 430)
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 21)).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Converting \(converter.currentJob?.input.name ?? "files")")
                        .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(converter.currentJob?.format.name ?? "")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.56))
                }
                Spacer()
                Text("\(converter.completedCount + converter.failedCount + 1) of \(converter.jobs.count)")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            if let value = converter.overallProgress {
                ProgressView(value: value).tint(.cyan)
            } else {
                ProgressView().tint(.cyan)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = converter.currentJob?.startedAt.map { context.date.timeIntervalSince($0) } ?? 0
                Text("\(converter.overallProgress.map { "\(Int($0 * 100))% · " } ?? "")\(duration(elapsed)) elapsed")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
            HStack {
                if let remaining = converter.currentJob?.progress?.remaining {
                    Text("About \(duration(remaining)) remaining")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.54))
                }
                Spacer()
                if converter.jobs.count > 1 {
                    Button("Cancel current") { converter.cancelCurrent() }
                }
                Button("Cancel all") { converter.cancelAll() }
                    .font(.system(size: 11))
            }
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: converter.failedCount == 0 && !converter.outputs.isEmpty
                      ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(converter.failedCount == 0 && !converter.outputs.isEmpty ? .green : .orange)
                    .symbolEffect(.bounce, value: converter.stage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(converter.failedCount == 0 && !converter.outputs.isEmpty
                         ? "Conversion complete" : "Conversion finished")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(converter.completedCount) complete · \(converter.failedCount) failed" +
                         (converter.cancelledCount > 0 ? " · \(converter.cancelledCount) cancelled" : ""))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Button { converter.close() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17)).foregroundStyle(.white.opacity(0.5))
                }
            }
            if let output = converter.outputs.first {
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: output.path))
                        .resizable().scaledToFit().frame(width: 22, height: 22)
                    Text(output.lastPathComponent)
                        .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(fileSize(output)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                }
                .onDrag { NSItemProvider(contentsOf: output) ?? NSItemProvider() }
            }
            if let message = converter.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
            }
            HStack(spacing: 10) {
                if !converter.outputs.isEmpty {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(converter.outputs)
                    }
                    Button("Open") { converter.outputs.forEach { NSWorkspace.shared.open($0) } }
                }
                if converter.failedCount > 0 {
                    Button("Retry failed") { converter.retryFailed() }
                    Button(showDetails ? "Hide details" : "Details") { showDetails.toggle() }
                }
                if let next = converter.nextCategory {
                    Button("Next: \(next.rawValue)") { converter.continueWithNextCategory() }
                }
                Spacer()
            }
            .font(.system(size: 11))
            if showDetails, let details = converter.technicalDetails {
                Text(details).font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48)).lineLimit(2)
            }
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let amount = max(0, Int(seconds))
        return String(format: "%02d:%02d", amount / 60, amount % 60)
    }

    private func fileSize(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
