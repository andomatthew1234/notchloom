import AppKit
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
    @EnvironmentObject private var vm: BoringViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var converter = ConversionManager.shared
    @ObservedObject private var preferences = ConversionPreferences.shared
    @State private var choosingFormat = false
    @State private var showingSettings = false
    @State private var search = ""
    @State private var showDetails = false
    @State private var resultAnimationTrigger = 0
    @FocusState private var searchFocused: Bool

    private var selected: ConversionFormat? { converter.selectedFormat }
    private var first: ConversionInput? { converter.categoryInputs.first }
    private var panelAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.86)
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
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.top, 10).padding(.bottom, 14)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id("\(converter.stage)-\(choosingFormat)-\(showingSettings)")
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 9)))
        }
        .padding(.horizontal, 22)
        .padding(.top, 11)
        .padding(.bottom, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ScrollGestureExclusionArea())
        .onHover(perform: converter.hoverChanged)
        .animation(panelAnimation, value: converter.stage)
        .animation(panelAnimation, value: choosingFormat)
        .animation(panelAnimation, value: showingSettings)
        .onChange(of: choosingFormat) { _, isChoosing in
            if isChoosing {
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
            VStack(alignment: .leading, spacing: 1) {
                Text(converter.stage == .running ? "Converting" :
                     converter.categoryInputs.count > 1 ? "Convert Files" : "Convert File")
                    .font(.system(size: 17, weight: .semibold))
                if converter.stage == .running || converter.jobs.count > 1 {
                    Text("\(converter.jobs.count > 0 ? converter.jobs.count : converter.categoryInputs.count) files")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.48))
                }
            }
            Spacer()
            Button { converter.close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close Convert")
            .accessibilityLabel("Close Convert")
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
                            .symbolEffect(.pulse, value: converter.selectedFormatID)
                            .frame(maxWidth: .infinity)
                        formatChip(selected?.name ?? "Choose format", caption: "TO")
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 51)
                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("OUTPUT FORMAT")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8).foregroundStyle(.white.opacity(0.47))
                        Button {
                            search = ""
                            withAnimation(panelAnimation) { choosingFormat = true }
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
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(minWidth: 68, minHeight: 34)
                Spacer()
                Button {
                    withAnimation(panelAnimation) { showingSettings = true }
                } label: {
                    Label("Advanced Settings", systemImage: "slider.horizontal.3")
                        .frame(minHeight: 34).padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.82))
                Button { converter.start() } label: {
                    Label(converter.categoryInputs.count > 1 ? "Convert all" : "Convert", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 17).frame(height: 36)
                        .background(.cyan, in: Capsule()).foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(selected == nil)
            }
        }
    }

    private var fileCard: some View {
        HStack(spacing: 13) {
            Image(nsImage: first.map { NSWorkspace.shared.icon(forFile: $0.url.path) } ?? NSImage())
                .resizable().scaledToFit().frame(width: 49, height: 49)
                .frame(width: 58, height: 58)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text(converter.categoryInputs.count == 1 ? first?.name ?? "File" :
                     "\(converter.categoryInputs.count) files to convert")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text(first?.isDirectory == true ? "Folder" :
                     "\(first?.displayType ?? "File") · \(ByteCountFormatter.string(fromByteCount: converter.totalSize, countStyle: .file))")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
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
        }
        .frame(width: 155, alignment: .leading)
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
                Button("Done") { withAnimation(panelAnimation) { choosingFormat = false } }
                    .buttonStyle(.plain).foregroundStyle(.cyan)
            }
            TextField("Search formats", text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityLabel("Search conversion formats")
                .onSubmit {
                    if let format = filteredFormats.first {
                        converter.selectedFormatID = format.id
                        withAnimation(panelAnimation) { choosingFormat = false }
                    }
                }
                .onKeyPress(.escape) {
                    withAnimation(panelAnimation) { choosingFormat = false }
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
                                    withAnimation(panelAnimation) { choosingFormat = false }
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
                withAnimation(panelAnimation) { choosingFormat = false }
                return .handled
            }
        }
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Advanced Settings").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { withAnimation(panelAnimation) { showingSettings = false } }
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
                    Text("To \(converter.currentJob?.format.name ?? "output")")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.54))
                }
                Spacer()
                Text("\(min(converter.jobs.count, converter.completedCount + converter.failedCount + converter.cancelledCount + 1)) / \(converter.jobs.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(12)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Conversion progress")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if let value = converter.overallProgress {
                        Text("\(Int(value * 100))%")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.cyan)
                    }
                }
                if let value = converter.overallProgress {
                    ProgressView(value: value).tint(.cyan)
                } else {
                    ProgressView().tint(.cyan)
                }
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
            .padding(15)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
            Spacer(minLength: 0)
            HStack {
                Text("Notchloom stays available while files convert.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.46))
                Spacer()
                if converter.jobs.count > 1 {
                    Button("Cancel current") { converter.cancelCurrent() }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                        .frame(minHeight: 36)
                }
                Button(converter.jobs.count > 1 ? "Cancel all" : "Cancel") { converter.cancelAll() }
                    .buttonStyle(.plain).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(.white.opacity(0.11), in: Capsule())
            }
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 13) {
                Image(systemName: converter.failedCount == 0 && !converter.outputs.isEmpty
                      ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(converter.failedCount == 0 && !converter.outputs.isEmpty ? .green : .orange)
                    .symbolEffect(.bounce, value: resultAnimationTrigger)
                    .onAppear {
                        if !reduceMotion { resultAnimationTrigger += 1 }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(converter.failedCount == 0 && !converter.outputs.isEmpty
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
                ScrollView {
                    Text(details).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.52))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 72)
                .padding(9)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if !converter.outputs.isEmpty {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(converter.outputs)
                    }
                    .buttonStyle(.plain).frame(minHeight: 36)
                    Button("Open") { converter.outputs.forEach { NSWorkspace.shared.open($0) } }
                        .buttonStyle(.plain).frame(minHeight: 36)
                }
                if converter.failedCount > 0 {
                    Button("Retry failed") { converter.retryFailed() }
                        .buttonStyle(.plain).frame(minHeight: 36)
                    Button(showDetails ? "Hide details" : "Details") { withAnimation(panelAnimation) { showDetails.toggle() } }
                        .buttonStyle(.plain).frame(minHeight: 36)
                }
                Spacer()
                if let next = converter.nextCategory {
                    Button("Next: \(next.rawValue)") { converter.continueWithNextCategory() }
                        .buttonStyle(.plain).foregroundStyle(.cyan).frame(minHeight: 36)
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
