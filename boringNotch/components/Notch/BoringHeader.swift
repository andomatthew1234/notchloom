//
//  BoringHeader.swift
//  boringNotch
//
//  Created by Harsh Vardhan Goswami on 04/08/24.
//

import Defaults
import SwiftUI

struct BoringHeader: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared
    @Default(.settingsIconInNotch) private var showSettings

    private var showsTabs: Bool {
        coordinator.alwaysShowTabs || (!tvm.isEmpty && Defaults[.boringShelf])
            || coordinator.currentView == .tools || coordinator.currentView == .shelf
    }

    private var headerHeight: CGFloat {
        max(36, vm.effectiveClosedNotchHeight)
    }

    private var contentWidth: CGFloat {
        let cornerInset = Defaults[.cornerRadiusScaling]
            ? cornerRadiusInsets.opened.top : cornerRadiusInsets.opened.bottom
        return max(vm.closedNotchSize.width, vm.notchSize.width - 2 * (cornerInset + 12))
    }

    var body: some View {
        let sideWidth = max(0, (contentWidth - vm.closedNotchSize.width) / 2)

        HStack(spacing: 0) {
            HStack(spacing: 0) {
                if showSettings {
                    Button {
                        SettingsWindowController.shared.showWindow()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.09), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Notchloom Settings")
                    .accessibilityLabel("Notchloom Settings")
                }
                Spacer(minLength: 6)
                if showsTabs {
                    TabSelectionView()
                } else {
                    Button {
                        withAnimation(.smooth) { coordinator.currentView = .tools }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help("Open Overview")
                }
            }
            .padding(.trailing, 6)
            .frame(width: sideWidth, height: headerHeight)

            Rectangle()
                .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                .frame(width: vm.closedNotchSize.width, height: headerHeight)
                .mask { NotchShape() }

            utilityHUD
                .frame(width: sideWidth, height: headerHeight, alignment: .trailing)
        }
        .frame(width: contentWidth, height: headerHeight)
        // NotchLayout is leading-aligned to the wider player content. Bring the
        // camera spacer back to the screen center while keeping tabs beside it.
        .offset(x: -vm.closedNotchSize.width / 2)
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    @ViewBuilder
    private var utilityHUD: some View {
        if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
            OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                .padding(.trailing, 8)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }

    private func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
