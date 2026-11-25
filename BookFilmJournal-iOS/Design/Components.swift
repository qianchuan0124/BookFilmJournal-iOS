import SwiftUI

// MARK: - Page shell

struct PageScaffold<Header: View, Content: View>: View {
    var scrollTarget: Binding<String?>? = nil
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, 14)
            ScrollViewReader { proxy in
                ScrollView {
                    content
                        .padding(.bottom, 82)
                }
                .scrollIndicators(.hidden)
                .onChange(of: scrollTarget?.wrappedValue) { _, target in
                    guard let target else { return }
                    withAnimation(.easeOut(duration: 0.28)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    if let scrollTarget {
                        DispatchQueue.main.async {
                            scrollTarget.wrappedValue = nil
                        }
                    }
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

struct PageScaffoldNoScroll<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, 14)
            content
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

struct SheetScaffold<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.sheet.ignoresSafeArea())
    }
}

struct SheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(Theme.text4.opacity(0.55))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

struct SheetHeader: View {
    let title: String
    var leftTitle: String = L10n.Common.close
    var rightTitle: String? = nil
    var rightEmphasized: Bool = true
    var rightDisabled: Bool = false
    var onLeft: () -> Void
    var onRight: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Text(title)
                .font(.appNav)
                .foregroundStyle(Theme.text)
            HStack {
                Button(leftTitle, action: onLeft)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text2)
                    .buttonStyle(.borderless)
                Spacer()
                if let rightTitle, let onRight {
                    Button(rightTitle, action: onRight)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(rightEmphasized ? Theme.gold : Theme.text2)
                        .buttonStyle(.borderless)
                        .disabled(rightDisabled)
                        .opacity(rightDisabled ? 0.4 : 1)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

struct NavHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var backLabel: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        ZStack {
            Text(title)
                .font(.appNav)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                        if let backLabel {
                            Text(backLabel)
                                .font(.system(size: 16))
                        }
                    }
                    .foregroundStyle(Theme.gold)
                }
                .buttonStyle(.plain)
                Spacer()
                if let trailing {
                    trailing
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

// MARK: - Segments and chips

struct AppSegmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    var title: (Option) -> String
    var gold: Bool = false
    var compact: Bool = false
    var fitContent: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .font(.system(size: compact ? 12.5 : 14, weight: .semibold))
                        .foregroundStyle(selected ? (gold ? Color(hex: 0x241804) : Theme.text) : Theme.text2)
                        .frame(maxWidth: fitContent ? nil : .infinity)
                        .padding(.horizontal, fitContent ? 18 : 0)
                        .padding(.vertical, compact ? 5 : 7)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(gold ? Theme.goldBright : Theme.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct ChipItem: Identifiable, Hashable {
    let id: String
    let label: String
    var count: String? = nil
}

struct ChipBar: View {
    let items: [ChipItem]
    @Binding var selectedID: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(items) { item in
                    let selected = item.id == selectedID
                    Button {
                        selectedID = item.id
                    } label: {
                        HStack(spacing: 4) {
                            Text(item.label)
                            if let count = item.count {
                                Text(count)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(selected ? Theme.goldDeep.opacity(0.72) : Theme.text3)
                            }
                        }
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Theme.goldDeep : Theme.text2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selected ? Theme.goldSoft : Theme.surface)
                        .overlay(
                            Capsule().stroke(selected ? Theme.goldBorder : Theme.borderStrong, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Text and tags

struct SectionHeading: View {
    let title: String
    var trailing: String? = nil
    var trailingColor: Color = Theme.gold

    var body: some View {
        HStack {
            Text(title)
                .font(.appBodySmall)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.text2)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.appCaption)
                    .foregroundStyle(trailingColor)
            }
        }
        .padding(.horizontal, 2)
    }
}

struct TagView: View {
    enum Style {
        case gold, teal, read, wish, neutral, danger
    }

    let text: String
    var style: Style = .neutral

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var foreground: Color {
        switch style {
        case .gold: Theme.goldDeep
        case .teal: Theme.teal
        case .read: Theme.read
        case .wish: Theme.wish
        case .neutral: Theme.text3
        case .danger: Theme.danger
        }
    }

    private var background: Color {
        switch style {
        case .gold: Theme.goldSoft
        case .teal: Theme.readSoft
        case .read: Theme.readSoft
        case .wish: Theme.wishSoft
        case .neutral: Theme.subtle
        case .danger: Theme.dangerSoft
        }
    }
}

struct StarsView: View {
    let rating: Int
    var size: CGFloat = 10.5

    var body: some View {
        Text(rating == 0 ? L10n.Stats.notRated : String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating))
            .font(.system(size: size, weight: rating == 0 ? .regular : .medium))
            .foregroundStyle(rating == 0 ? Theme.text4 : Theme.star)
            .tracking(0.2)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Groups

struct InfoGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

struct FieldRow<Value: View>: View {
    let label: String
    var icon: AnyView? = nil
    var showDivider: Bool = true
    var hint: String? = nil
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                icon
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.appBody)
                    .foregroundStyle(Theme.text2)
                if let hint, !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.text4)
                }
            }
            Spacer(minLength: 8)
            value
                .font(.appBody)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if showDivider {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                    .padding(.leading, icon == nil ? 15 : 54)
            }
        }
    }
}

// MARK: - Buttons

struct GoldButtonStyle: ButtonStyle {
    var height: CGFloat = 48
    var radius: CGFloat = 13
    var font: Font = .appButton
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(Color(hex: 0x241804))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0xF4D083), Color(hex: 0xBC7C1D)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color(hex: 0x966012).opacity(0.24), radius: 8, y: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    var radius: CGFloat = 10
    var foreground: Color = Theme.text2
    var font: Font = .appButtonSmall
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Theme.subtle)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    var radius: CGFloat = 10
    var foreground: Color = Theme.text
    var font: Font = .appButtonSmall
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.borderStrong, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct IconCircleButton: View {
    let systemName: String
    var tint: Color = Theme.text
    var background: Color = Theme.subtle
    var size: CGFloat = 34
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text3)
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .onSubmit { onSubmit?() }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.text4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var title: String = L10n.Common.selectDate
    @Binding var date: Date
    @State private var draft: Date

    init(title: String = L10n.Common.selectDate, date: Binding<Date>) {
        self.title = title
        _date = date
        _draft = State(initialValue: date.wrappedValue)
    }

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(
                    title: title,
                    leftTitle: L10n.Common.close,
                    rightTitle: L10n.Common.done,
                    onLeft: { dismiss() },
                    onRight: {
                        date = draft
                        dismiss()
                    }
                )
            }
        } content: {
            DatePicker("", selection: $draft, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .tint(Theme.gold)
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.read)
            Text(message)
                .font(.system(size: 12.5, weight: .semibold))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(hex: 0x1C1914).opacity(0.92))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let value = message {
                    ToastView(message: value)
                        .padding(.top, 52)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: message)
            .onAppear {
                if message != nil { scheduleDismissal() }
            }
            .onChange(of: message) { _, value in
                if value != nil { scheduleDismissal() }
            }
    }

    private func scheduleDismissal() {
        let current = UUID()
        token = current
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard token == current else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                message = nil
            }
        }
    }
}

extension View {
    func toast(message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.text4)
            Text(title)
                .font(.appBody)
                .foregroundStyle(Theme.text3)
            if let detail {
                Text(detail)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text4)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

// MARK: - Tab bar

struct AppTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: selection == tab ? .semibold : .regular))
                        Text(tab.label)
                            .font(.system(size: 10.5, weight: selection == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selection == tab ? Theme.gold : Theme.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 58)
        .background(Theme.tabBar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
    }
}

// MARK: - Poster wall

struct PosterWallGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3),
            alignment: .leading,
            spacing: 14
        ) {
            content
        }
    }
}
