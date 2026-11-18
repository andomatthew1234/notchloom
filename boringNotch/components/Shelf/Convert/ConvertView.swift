import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct ConvertTargetView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .animation(reduceMotion ? .easeOut(duration: 0.15) :
            .spring(response: 0.32, dampingFraction: 0.82), value: targeted)
        .onChange(of: targeted) { _, value in vm.convertDropTargeting = value }
        .onDisappear { vm.convertDropTargeting = false }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard !providers.isEmpty else { return false }
            vm.dropEvent = true
            converter.prepare(providers: providers, screenID: vm.screenUUID)
            return true
        }
        .accessibilityLabel("Convert files")
        .help("Drop files here to choose a conversion format")
    }
}

struct ConvertPanelView: View {
    private enum Page: Equatable { case setup, formats, settings }
    @EnvironmentObject private var vm: BoringViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var converter = ConversionManager.shared
    @ObservedObject private var preferences = ConversionPreferences.shared
    @State private var page: Page = .setup
    @State private var search = ""
    @State private var showDetails = false
    @State private var resultAnimationTrigger = 0
    @State private var previewImage: NSImage?
    @FocusState private var searchFocused: Bool

    private var selected: ConversionFormat? { converter.selectedFormat }
    private var first: ConversionInput? { converter.categoryInputs.first }
    private var panelAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.9)
    }
    private var inputFormatName: String {
        first?.type.preferredFilenameExtension?.uppercased() ?? first?.displayType ?? "FILE"
    }
    private var filteredFormats: [ConversionFormat] {
        converter.formats.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                || $0.detail.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(.white.opacity(0.075)).frame(height: 1).padding(.top, 11).padding(.bottom, 15)
            Group {
                switch converter.stage {
                case .idle: EmptyView()
                case .preparing: loadingView
                case .setup:
                    switch page {
                    case .setup: setupView
                    case .formats: formatPicker
                    case .settings: settingsView
                    }
                case .running: progressView
                case .finished: resultView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 9)))
        }
        .padding(.horizontal, 22)
        .padding(.top, 11)
        .padding(.bottom, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ScrollGestureExclusionArea())
        .onHover(perform: converter.hoverChanged)
        .animation(panelAnimation, value: converter.stage)
        .animation(panelAnimation, value: page)
        .onChange(of: page) { _, newPage in
            if newPage == .formats {
                if let window = vm.hostWindow as? BoringNotchSkyLightWindow {
                    window.allowsConverterKeyboardFocus = true
                    window.makeKey()
                }
                Task { @MainActor in searchFocused = true }
            } else {
                releaseKeyboardFocus()
            }
        }
        .onChange(of: converter.stage) { _, stage in
            if stage != .setup { releaseKeyboardFocus() }
        }
        .onDisappear { releaseKeyboardFocus() }
        .task(id: first?.id) {
            previewImage = nil
            guard let input = first, !input.isDirectory else { return }
            let request = QLThumbnailGenerator.Request(
                fileAt: input.url, size: CGSize(width: 128, height: 128),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: [.thumbnail, .icon])
            previewImage = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }

    private func releaseKeyboardFocus() {
        searchFocused = false
        if let window = vm.hostWindow as? BoringNotchSkyLightWindow {
            window.resignKey()
            window.allowsConverterKeyboardFocus = false
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 34, height: 34)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .symbolEffect(.pulse, options: .repeating, isActive: converter.stage == .running && !reduceMotion)
            VStack(alignment: .leading, spacing: 1) {
                Text(converter.stage == .running ? "Converting" :
                     converter.categoryInputs.count > 1 ? "Convert Files" : "Convert File")
                    .font(.system(size: 17, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.48))
            }
            Spacer()
            Button { converter.close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(ConvertActionStyle(.close))
            .help("Close Convert")
            .accessibilityLabel("Close Convert")
        }
    }

    private var headerSubtitle: String {
        switch converter.stage {
        case .preparing: "Preparing your files"
        case .running: converter.jobs.count > 1 ? "\(converter.jobs.count) files in the queue" : "Your file is on its way"
        case .finished: converter.failedCount > 0 ? "Review the result" : "Ready to use"
        case .setup, .idle: converter.categoryInputs.count > 1
            ? "\(converter.categoryInputs.count) files · choose an output" : "Choose a format and make it yours"
        }
    }

    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Checking files…").font(.system(size: 14, weight: .medium))
            Spacer()
        }
        .padding(.top, 50)
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    fileCard

                    HStack(spacing: 12) {
                        formatChip(inputFormatName, caption: "FROM")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.pulse, value: converter.selectedFormatID)
                            .frame(maxWidth: .infinity)
                        formatChip(selected?.name ?? "Choose format", caption: "TO")
                    }
                    .frame(height: 57)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("OUTPUT FORMAT")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8).foregroundStyle(.white.opacity(0.47))
                        Button {
                            search = ""
                            withAnimation(panelAnimation) { page = .formats }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selected.map { icon(for: $0.category) } ?? "questionmark.circle")
                                    .font(.system(size: 17)).foregroundStyle(.cyan)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selected?.name ?? "No compatible formats")
                                        .font(.system(size: 13, weight: .semibold))
                                    if let selected {
                                        Text(selected.detail).font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.53)).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .padding(.horizontal, 12).frame(height: 48)
                            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                        .disabled(converter.formats.isEmpty)
                        .accessibilityLabel("Convert to \(selected?.name ?? "No compatible formats")")
                    }
                    if let note = converter.message {
                        Text(note).font(.system(size: 11)).foregroundStyle(.orange)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            HStack(spacing: 10) {
                Button("Cancel") { converter.close() }
                    .buttonStyle(ConvertActionStyle(.secondary))
                Spacer()
                Button {
                    withAnimation(panelAnimation) { page = .settings }
                } label: {
                    Label("Advanced Settings", systemImage: "slider.horizontal.3")
                        .frame(minHeight: 34).padding(.horizontal, 10)
                }
                .buttonStyle(ConvertActionStyle(.secondary))
                Button { converter.start() } label: {
                    Label(converter.categoryInputs.count > 1 ? "Convert all" : "Convert", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 17).frame(height: 36)
                }
                .buttonStyle(ConvertActionStyle(.primary))
                .disabled(selected == nil)
            }
        }
    }

    private var fileCard: some View {
        HStack(spacing: 13) {
            Image(nsImage: previewImage ?? first.map { NSWorkspace.shared.icon(forFile: $0.url.path) } ?? NSImage())
                .resizable().scaledToFit().frame(width: 61, height: 61)
                .frame(width: 72, height: 72)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(converter.categoryInputs.count == 1 ? first?.name ?? "File" :
                     "\(converter.categoryInputs.count) files to convert")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text(first?.isDirectory == true ? "Folder" :
                     "\(first?.displayType ?? "File") · \(ByteCountFormatter.string(fromByteCount: converter.totalSize, countStyle: .file))")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                if let duration = first?.duration {
                    Text("\(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60)) duration")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
            }
            Spacer(minLength: 6)
            if converter.availableCategories.count > 1 {
                Menu {
                    ForEach(converter.availableCategories) { category in
                        Button(category.rawValue) { converter.selectCategory(category) }
                    }
                } label: {
                    Text(converter.selectedCategory.rawValue)
                        .font(.system(size: 11, weight: .medium))
                }
            }
        }
        .padding(11)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.075)))
    }

    private func formatChip(_ text: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption).font(.system(size: 9, weight: .semibold))
                .tracking(0.6).foregroundStyle(.white.opacity(0.43))
            Text(text).font(.system(size: 12, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 12)
        .frame(width: 155, height: 54, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
    }

    private func icon(for category: ConversionCategory) -> String {
        switch category {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .document: "doc.text"
        case .ebook: "book.closed"
        case .archive: "archivebox"
        }
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose output format").font(.system(size: 15, weight: .semibold))
                    Text("Only formats available for this file are shown")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.53))
                }
                Spacer()
                Button("Done") { withAnimation(panelAnimation) { page = .setup } }
                    .buttonStyle(.plain).foregroundStyle(.cyan)
            }
            TextField("Search formats", text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityLabel("Search conversion formats")
                .onSubmit {
                    if let format = filteredFormats.first {
                        converter.selectedFormatID = format.id
                        withAnimation(panelAnimation) { page = .setup }
                    }
                }
                .onKeyPress(.escape) {
                    withAnimation(panelAnimation) { page = .setup }
                    return .handled
                }
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(ConversionCategory.allCases) { category in
                        let options = filteredFormats.filter { $0.category == category }
                        if !options.isEmpty {
                            Text(category.rawValue.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.8).foregroundStyle(.white.opacity(0.48))
                                .padding(.top, 4)
                            ForEach(options) { format in
                                Button {
                                    converter.selectedFormatID = format.id
                                    withAnimation(panelAnimation) { page = .setup }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: icon(for: category))
                                            .font(.system(size: 17)).foregroundStyle(.cyan)
                                            .frame(width: 27)
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(format.name).font(.system(size: 13, weight: .semibold))
                                                if format.id == converter.formats.first?.id {
                                                    Text("Suggested")
                                                        .font(.system(size: 9, weight: .medium))
                                                        .foregroundStyle(.cyan.opacity(0.85))
                                                }
                                            }
                                            Text(format.detail).font(.system(size: 11))
                                                .foregroundStyle(.white.opacity(0.52)).lineLimit(1)
                                        }
                                        Spacer()
                                        if format.id == converter.selectedFormatID {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.cyan)
                                        }
                                    }
                                    .padding(.horizontal, 12).frame(height: 48)
                                    .background(.white.opacity(format.id == converter.selectedFormatID ? 0.13 : 0.055),
                                                in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(format.name), \(format.detail)")
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: .infinity)
            .onKeyPress(.escape) {
                withAnimation(panelAnimation) { page = .setup }
                return .handled
            }
        }
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Advanced Settings").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { withAnimation(panelAnimation) { page = .setup } }
                    .buttonStyle(.plain).foregroundStyle(.cyan)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if converter.selectedCategory == .image || converter.selectedCategory == .video ||
                        converter.selectedCategory == .audio {
                        settingRow("Quality") {
                            Picker("Quality", selection: $converter.preset) {
                                ForEach(ConversionPreset.allCases) { choice in
                                    Text(choice.rawValue).tag(choice)
                                }
                            }
                            .labelsHidden().frame(width: 190)
                        }
                    }
                    settingRow("Save to") {
                        Menu {
                            Button("Beside original") { preferences.useOriginalFolder() }
                            Button("Choose folder…") { preferences.chooseFolder() }
                        } label: {
                            Text(preferences.folderName).lineLimit(1)
                                .frame(maxWidth: 190, alignment: .trailing)
                            Image(systemName: "chevron.down").font(.system(size: 10))
                        }
                    }
                    settingRow("Filename") {
                        Picker("Filename", selection: $preferences.naming) {
                            ForEach(ConversionPreferences.Naming.allCases) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }
                        .labelsHidden().frame(width: 190)
                    }
                    settingRow("If name exists") {
                        Picker("If name exists", selection: $preferences.collision) {
                            ForEach(ConversionCollision.allCases) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }
                        .labelsHidden().frame(width: 190)
                    }
                    settingRow("Keep metadata") {
                        Toggle("Keep metadata", isOn: $preferences.preserveMetadata)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    Text("The original is never replaced. Some formats cannot retain every type of metadata or visual detail.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.47))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 3)
                }
            }
            .scrollIndicators(.visible)
        }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 10)
            content()
        }
        .frame(minHeight: 38)
        .padding(.horizontal, 12)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(nsImage: converter.currentJob.map { NSWorkspace.shared.icon(forFile: $0.input.url.path) } ?? NSImage())
                    .resizable().scaledToFit().frame(width: 45, height: 45)
                VStack(alignment: .leading, spacing: 3) {
                    Text(converter.currentJob?.input.name ?? "Preparing next file")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Text("\(converter.currentJob?.input.type.preferredFilenameExtension?.uppercased() ?? "FILE")  →  \(converter.currentJob?.format.name ?? "output")")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.54))
                }
                Spacer()
                Text("\(min(converter.jobs.count, converter.completedCount + converter.failedCount + converter.cancelledCount + 1)) / \(converter.jobs.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(13)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(converter.overallProgress == nil ? "Working on your file" : "Conversion progress")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if let value = converter.overallProgress {
                        Text("\(Int(value * 100))%")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.cyan)
                    }
                }
                ConversionProgressTrack(fraction: converter.overallProgress, reduceMotion: reduceMotion)
                    .frame(height: 11)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = converter.currentJob?.startedAt.map { context.date.timeIntervalSince($0) } ?? 0
                    HStack {
                        Text("\(duration(elapsed)) elapsed")
                        Spacer()
                        if let remaining = converter.currentJob?.progress?.remaining, remaining.isFinite {
                            Text("About \(duration(remaining)) remaining")
                        }
                    }
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.51))
                }
            }
            .padding(17)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            Spacer(minLength: 0)
            HStack {
                Text("The original stays untouched.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.46))
                Spacer()
                if converter.jobs.count > 1 {
                    Button("Cancel current") { converter.cancelCurrent() }
                        .buttonStyle(ConvertActionStyle(.secondary))
                }
                Button(converter.jobs.count > 1 ? "Cancel all" : "Cancel Conversion") { converter.cancelAll() }
                    .buttonStyle(ConvertActionStyle(.secondary))
            }
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 13) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 13) {
                Image(systemName: converter.presentation == .cancelled ? "xmark.circle.fill" :
                      converter.failedCount == 0 && !converter.outputs.isEmpty
                      ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(converter.presentation == .cancelled ? .white.opacity(0.7) :
                        converter.failedCount == 0 && !converter.outputs.isEmpty ? .green : .orange)
                    .symbolEffect(.bounce, value: resultAnimationTrigger)
                    .onAppear {
                        if !reduceMotion { resultAnimationTrigger += 1 }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(converter.presentation == .cancelled ? "Conversion canceled" :
                         converter.failedCount == 0 && !converter.outputs.isEmpty
                         ? "Conversion complete" : "Conversion finished")
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(converter.completedCount) complete · \(converter.failedCount) failed" +
                         (converter.cancelledCount > 0 ? " · \(converter.cancelledCount) cancelled" : ""))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }
            if let output = converter.outputs.first {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: output.path))
                        .resizable().scaledToFit().frame(width: 45, height: 45)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(output.lastPathComponent)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                        Text(fileSize(output)).font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Image(systemName: "hand.draw")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.4))
                }
                .padding(12)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                .onDrag { NSItemProvider(contentsOf: output) ?? NSItemProvider() }
                .help("Drag the converted file into Finder or another app")
            }
            if let message = converter.message {
                Text(message).font(.system(size: 12)).foregroundStyle(.orange)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            if showDetails, let details = converter.technicalDetails {
                Text(details).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
            }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            HStack(spacing: 10) {
                if !converter.outputs.isEmpty {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(converter.outputs)
                    }
                    .buttonStyle(ConvertActionStyle(.secondary))
                    Button("Open") { converter.outputs.forEach { NSWorkspace.shared.open($0) } }
                        .buttonStyle(ConvertActionStyle(.primary))
                }
                if converter.failedCount > 0 {
                    Button("Retry failed") { converter.retryFailed() }
                    .buttonStyle(ConvertActionStyle(.secondary))
                    Button(showDetails ? "Hide details" : "Details") { withAnimation(panelAnimation) { showDetails.toggle() } }
                        .buttonStyle(ConvertActionStyle(.secondary))
                }
                Spacer()
                if let next = converter.nextCategory {
                    Button("Next: \(next.rawValue)") { converter.continueWithNextCategory() }
                        .buttonStyle(ConvertActionStyle(.secondary))
                }
            }
            .font(.system(size: 12, weight: .medium))
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

private struct ConvertActionStyle: ButtonStyle {
    enum Emphasis { case primary, secondary, close }
    let emphasis: Emphasis
    init(_ emphasis: Emphasis) { self.emphasis = emphasis }

    func makeBody(configuration: Configuration) -> some View {
        ButtonContent(configuration: configuration, emphasis: emphasis)
    }

    private struct ButtonContent: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let configuration: Configuration
        let emphasis: Emphasis
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(emphasis == .primary ? Color.black : Color.white.opacity(hovered ? 1 : 0.82))
                .padding(.horizontal, emphasis == .close ? 0 : 13)
                .frame(minHeight: emphasis == .close ? 32 : 36)
                .background(background, in: emphasis == .close
                    ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 11)))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
                .onHover { hovered = $0 }
        }

        private var background: Color {
            if emphasis == .primary { return .cyan.opacity(configuration.isPressed ? 0.8 : hovered ? 0.91 : 1) }
            return .white.opacity(configuration.isPressed ? 0.18 : hovered ? 0.13 : 0.075)
        }
    }
}

private struct ConversionProgressTrack: View {
    let fraction: Double?
    let reduceMotion: Bool
    @State private var sweep = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                if let fraction {
                    let filled = width * min(1, max(0, fraction))
                    Capsule().fill(.cyan)
                        .frame(width: filled)
                        .overlay(alignment: .leading) {
                            if !reduceMotion && filled > 20 {
                                LinearGradient(colors: [.clear, .white.opacity(0.34), .clear],
                                               startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 48)
                                    .offset(x: sweep ? filled : -48)
                                    .mask(Capsule().frame(width: filled))
                            }
                        }
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: fraction)
                } else {
                    Capsule().fill(.cyan.opacity(0.85))
                        .frame(width: max(44, width * 0.27))
                        .offset(x: reduceMotion ? 0 : sweep ? width : -max(44, width * 0.27))
                }
            }
            .clipShape(Capsule())
            .animation(reduceMotion ? nil : .linear(duration: 1.85).repeatForever(autoreverses: false), value: sweep)
        }
        .onAppear { sweep = true }
        .accessibilityLabel(fraction.map { "Conversion \(Int($0 * 100)) percent complete" }
                            ?? "Conversion in progress")
    }
}
