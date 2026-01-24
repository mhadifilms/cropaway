//
//  GlassEffectHelpers.swift
//  cropaway
//
//  Compatibility helpers for macOS Tahoe Liquid Glass effects.
//  Uses Apple's Liquid Glass design language for controls and navigation elements.
//
//  References:
//  - https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
//  - https://github.com/conorluddy/LiquidGlassReference
//

import SwiftUI

// MARK: - View Extensions

extension View {
    /// Applies a glass background effect for toolbar areas.
    @ViewBuilder
    func toolbarGlassBackground() -> some View {
        if #available(macOS 26.0, *) {
            self
                .background(.regularMaterial)
                .glassEffect(.regular, in: .rect)
        } else {
            self.background(Color(NSColor.windowBackgroundColor))
        }
    }

    /// Applies a glass background effect for control containers.
    @ViewBuilder
    func controlContainerGlassBackground(cornerRadius: CGFloat = 8) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Applies a clear glass background (more transparent for media-rich contexts).
    @ViewBuilder
    func clearGlassBackground() -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.clear, in: .rect)
        } else {
            self.background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        }
    }

    /// Applies interactive glass effect to a button with scaling, bounce, and shimmer.
    @ViewBuilder
    func interactiveGlassButton(isSelected: Bool = false, cornerRadius: CGFloat = 6) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(
                    isSelected ? .regular.tint(.accentColor) : .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor).opacity(0.3))
            )
        }
    }

    /// Applies circular interactive glass effect.
    @ViewBuilder
    func circularGlassButton(isSelected: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(
                    isSelected ? .regular.tint(.accentColor) : .regular.interactive(),
                    in: .circle
                )
        } else {
            self
                .background(Circle().fill(isSelected ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor).opacity(0.3)))
        }
    }

    /// Applies capsule-shaped interactive glass effect.
    @ViewBuilder
    func capsuleGlassButton(isSelected: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(
                    isSelected ? .regular.tint(.accentColor) : .regular.interactive(),
                    in: .capsule
                )
        } else {
            self
                .background(Capsule().fill(isSelected ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor).opacity(0.3)))
        }
    }

    /// Applies tinted glass effect with a custom color.
    @ViewBuilder
    func tintedGlassEffect(_ color: Color, cornerRadius: CGFloat = 8) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(color), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self
                .background(RoundedRectangle(cornerRadius: cornerRadius).fill(color.opacity(0.2)))
        }
    }

    // MARK: - Sidebar Glass Effects

    /// Applies glass background to sidebar list.
    @ViewBuilder
    func sidebarGlassBackground() -> some View {
        if #available(macOS 26.0, *) {
            self.background(.regularMaterial)
        } else {
            self.background(Color(NSColor.windowBackgroundColor))
        }
    }

    /// Applies circular glass button style for sidebar.
    @ViewBuilder
    func sidebarGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .contentShape(Circle())
        }
    }

    /// Applies capsule glass style for sidebar elements.
    @ViewBuilder
    func sidebarGlassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self
                .background(Capsule().fill(Color.primary.opacity(0.04)))
        }
    }

    // MARK: - Sheet/Modal Glass Effects

    /// Applies glass background for modal sheets.
    @ViewBuilder
    func sheetGlassBackground() -> some View {
        if #available(macOS 26.0, *) {
            self
                .background(.regularMaterial)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else {
            self.background(Color(NSColor.windowBackgroundColor))
        }
    }

    /// Applies glass effect to empty state containers.
    @ViewBuilder
    func emptyStateGlassBackground() -> some View {
        if #available(macOS 26.0, *) {
            self
                .background(.ultraThinMaterial)
                .glassEffect(.clear, in: .rect(cornerRadius: 16))
        } else {
            self
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Content Area Glass Effects

    /// Applies glass background for main content areas (like detail view backgrounds).
    @ViewBuilder
    func contentAreaGlassBackground() -> some View {
        if #available(macOS 26.0, *) {
            self.background(.regularMaterial)
        } else {
            self.background(Color(NSColor.windowBackgroundColor))
        }
    }
}

// MARK: - Glass Effect Container

/// A container view that wraps content in a glass effect on macOS 26+.
/// On macOS 26+, this uses SwiftUI's native GlassEffectContainer for morphing support.
struct GlassEffectContainer<Content: View>: View {
    let spacing: CGFloat
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 20, cornerRadius: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            // Native GlassEffectContainer enables morphing between glass elements
            SwiftUI.GlassEffectContainer(spacing: spacing) {
                content()
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
            }
        } else {
            content()
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Interactive Glass Button Container

/// A container for a group of interactive glass buttons that can morph together.
struct GlassButtonGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 2, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            SwiftUI.GlassEffectContainer(spacing: spacing) {
                content()
            }
            .padding(4)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        } else {
            HStack(spacing: spacing) {
                content()
            }
            .padding(4)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Glass Toolbar Button Style

/// A button style that applies liquid glass effects for toolbar buttons.
struct LiquidGlassButtonStyle: ButtonStyle {
    let isSelected: Bool
    let cornerRadius: CGFloat

    init(isSelected: Bool = false, cornerRadius: CGFloat = 6) {
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .fontWeight(isSelected ? .semibold : .regular)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .interactiveGlassButton(isSelected: isSelected, cornerRadius: cornerRadius)
    }
}

// MARK: - Glass Segmented Control Style

/// A custom style for segmented pickers using liquid glass.
struct GlassSegmentedStyle: View {
    let options: [String]
    let icons: [String]
    @Binding var selection: Int

    var body: some View {
        if #available(macOS 26.0, *) {
            SwiftUI.GlassEffectContainer(spacing: 2) {
                HStack(spacing: 2) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            withAnimation(.bouncy(duration: 0.3)) {
                                selection = index
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if index < icons.count {
                                    Image(systemName: icons[index])
                                        .font(.system(size: 11))
                                }
                                Text(option)
                                    .font(.system(size: 11))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selection == index ? Color.accentColor : Color.primary)
                        .glassEffect(
                            selection == index ? .regular.tint(.accentColor) : .regular.interactive(),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                }
            }
        } else {
            Picker("", selection: $selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Text(option).tag(index)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
