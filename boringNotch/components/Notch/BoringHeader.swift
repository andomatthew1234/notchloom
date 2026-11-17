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
                Spacer(minLength: 0)
                if showsTabs {
                    TabSelectionView()
                        .offset(x: 12)
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
            .padding(.trailing, 4)
            .frame(width: sideWidth, height: headerHeight)

            Rectangle()
                .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                .frame(width: vm.closedNotchSize.width, height: headerHeight)
                .mask { NotchShape() }

            HStack(spacing: 6) {
                utilityHUD
                Spacer(minLength: 0)
                if showSettings {
                    Button {
                        SettingsWindowController.shared.showWindow()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(width: 29, height: 29)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Notchloom Settings")
                    .accessibilityLabel("Notchloom Settings")
                }
            }
            .padding(.trailing, 4)
            .frame(width: sideWidth, height: headerHeight)
        }
        .frame(width: contentWidth, height: headerHeight)
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
