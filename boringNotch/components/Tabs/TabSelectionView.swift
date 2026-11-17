//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    var id: NotchViews { view }
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Now Playing", icon: "play.circle.fill", view: .home),
    TabModel(label: "Overview", icon: "square.grid.2x2.fill", view: .tools),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) private var shelfEnabled
    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                if tab.view != .shelf || shelfEnabled {
                    Button {
                        withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
                            coordinator.currentView = tab.view
                        }
                    } label: {
                        VStack(spacing: 0) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(tab.label)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(coordinator.currentView == tab.view ? .white : .white.opacity(0.68))
                        .padding(.horizontal, 3)
                        .frame(height: 27)
                        .lineLimit(1)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if coordinator.currentView == tab.view {
                            Capsule()
                                .fill(.white.opacity(0.16))
                                .matchedGeometryEffect(id: "selectedTab", in: selectionAnimation)
                        }
                    }
                    .accessibilityAddTraits(coordinator.currentView == tab.view ? .isSelected : [])
                }
            }
        }
        .padding(2)
        .background(.white.opacity(0.07), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch view")
        .onChange(of: shelfEnabled) { _, enabled in
            if !enabled && coordinator.currentView == .shelf {
                withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
                    coordinator.currentView = .home
                }
            }
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
