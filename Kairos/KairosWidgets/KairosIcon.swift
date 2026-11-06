import SwiftUI

/// Portable MIT-licensed Phosphor vectors. The same path data is used by Android.
enum KairosIconCatalog {
    static let assets: [String: String] = [
        "accessibility": "kairos_person_arms_spread",
        "archivebox": "kairos_archive",
        "arrow.counterclockwise": "kairos_arrow_counter_clockwise",
        "arrow.down": "kairos_arrow_down",
        "arrow.turn.down.right": "kairos_arrow_elbow_down_right",
        "arrow.up": "kairos_arrow_up",
        "arrow.up.and.down": "kairos_arrows_down_up",
        "arrow.up.right": "kairos_arrow_up_right",
        "bell.badge": "kairos_bell_ringing",
        "bell.badge.fill": "kairos_bell_ringing_fill",
        "bell.fill": "kairos_bell_fill",
        "birthday.cake": "kairos_cake",
        "bubble.left.and.bubble.right": "kairos_chats",
        "bubble.left.and.bubble.right.fill": "kairos_chats_fill",
        "calendar": "kairos_calendar_blank",
        "calendar.badge.clock": "kairos_calendar_dots",
        "calendar.badge.plus": "kairos_calendar_plus",
        "chart.bar.fill": "kairos_chart_bar_fill",
        "chart.bar.xaxis": "kairos_chart_bar",
        "checklist": "kairos_list_checks",
        "checkmark": "kairos_check",
        "checkmark.circle": "kairos_check_circle",
        "checkmark.circle.fill": "kairos_check_circle_fill",
        "checkmark.seal.fill": "kairos_seal_check_fill",
        "checkmark.shield.fill": "kairos_shield_check_fill",
        "chevron.down": "kairos_caret_down",
        "chevron.left": "kairos_caret_left",
        "chevron.right": "kairos_caret_right",
        "chevron.up": "kairos_caret_up",
        "circle": "kairos_circle",
        "circle.lefthalf.filled": "kairos_circle_half",
        "clock": "kairos_clock",
        "ellipsis": "kairos_dots_three",
        "ellipsis.circle": "kairos_dots_three_circle",
        "envelope.badge.shield.half.filled": "kairos_envelope_simple",
        "exclamationmark.circle": "kairos_warning_circle",
        "exclamationmark.circle.fill": "kairos_warning_circle_fill",
        "exclamationmark.triangle": "kairos_warning",
        "face.smiling": "kairos_smiley",
        "flame.fill": "kairos_fire_fill",
        "folder": "kairos_folder",
        "folder.badge.plus": "kairos_folder_plus",
        "gear": "kairos_gear",
        "gearshape.fill": "kairos_gear_fill",
        "globe": "kairos_globe",
        "hand.raised.fill": "kairos_hand_palm_fill",
        "house.fill": "kairos_house_fill",
        "info.circle": "kairos_info",
        "line.3.horizontal.decrease": "kairos_funnel",
        "list.bullet": "kairos_list_bullets",
        "list.bullet.clipboard": "kairos_clipboard_text",
        "lock.fill": "kairos_lock_fill",
        "magnifyingglass": "kairos_magnifying_glass",
        "pause.fill": "kairos_pause_fill",
        "pencil": "kairos_pencil_simple",
        "person.crop.circle": "kairos_user_circle",
        "person.crop.circle.fill": "kairos_user_circle_fill",
        "play.fill": "kairos_play_fill",
        "plus": "kairos_plus",
        "rectangle.portrait.and.arrow.right": "kairos_sign_out",
        "repeat": "kairos_repeat",
        "sidebar.left": "kairos_sidebar_simple",
        "sparkles": "kairos_sparkle",
        "speaker.wave.2": "kairos_speaker_high",
        "square.and.pencil": "kairos_note_pencil",
        "square.stack.3d.up": "kairos_stack",
        "square.stack.3d.up.fill": "kairos_stack_fill",
        "stop.fill": "kairos_stop_fill",
        "text.alignleft": "kairos_text_align_left",
        "timer": "kairos_timer",
        "trash": "kairos_trash",
        "tray": "kairos_tray",
        "trophy.fill": "kairos_trophy_fill",
        "wifi.slash": "kairos_wifi_slash",
        "xmark": "kairos_x",
        "xmark.circle": "kairos_x_circle",
        "xmark.circle.fill": "kairos_x_circle_fill"
    ]

    static func asset(for symbol: String) -> String {
        guard let asset = assets[symbol] else {
            assertionFailure("Unmapped Kairos icon: \(symbol)")
            return "kairos_warning"
        }
        return asset
    }
}

/// Explicit point size preserves the former symbol metrics; Dynamic Type scales it.
/// Weight is part of the shared vector, so platform font weights cannot alter the glyph.
struct KairosIcon: View {
    private let symbol: String
    private let inheritsFontSize: Bool
    private let decorative: Bool
    @Environment(\.self) private var environment
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 17

    init(_ symbol: String, size: CGFloat? = nil, decorative: Bool = false) {
        self.symbol = symbol
        self.decorative = decorative
        inheritsFontSize = size == nil
        _size = ScaledMetric(wrappedValue: size ?? 17, relativeTo: .body)
    }

    private var pointSize: CGFloat {
        if inheritsFontSize, #available(iOS 26.0, *) {
            return (environment.font ?? .body).resolve(in: environment.fontResolutionContext).pointSize
        }
        return size
    }

    private var accessibilityTitle: String {
        switch symbol {
        case "plus": return "Add"
        case "xmark", "xmark.circle", "xmark.circle.fill": return "Close"
        case "pencil", "square.and.pencil": return "Edit"
        case "trash": return "Delete"
        case "magnifyingglass": return "Search"
        case "ellipsis", "ellipsis.circle": return "More options"
        case "circle": return "Not completed"
        case "checkmark", "checkmark.circle", "checkmark.circle.fill": return "Completed"
        case "play.fill": return "Start"
        case "pause.fill": return "Pause"
        case "stop.fill": return "Stop"
        case "chevron.left": return "Previous"
        case "chevron.right": return "Next"
        case "person.crop.circle", "person.crop.circle.fill": return "Profile"
        default: return symbol.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " ")
        }
    }

    var body: some View {
        Image(KairosIconCatalog.asset(for: symbol))
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: pointSize, height: pointSize)
            .accessibilityLabel(Text(accessibilityTitle))
            .accessibilityHidden(decorative)
    }
}

extension Label where Title == Text, Icon == KairosIcon {
    init(_ title: LocalizedStringKey, sharedIcon: String) {
        self.init { Text(title) } icon: { KairosIcon(sharedIcon, decorative: true) }
    }

    init<S: StringProtocol>(_ title: S, sharedIcon: String) {
        self.init { Text(title) } icon: { KairosIcon(sharedIcon, decorative: true) }
    }
}

extension Button where Label == SwiftUI.Label<Text, KairosIcon> {
    init(_ title: LocalizedStringKey, sharedIcon: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, sharedIcon: sharedIcon) }
    }

    init<S: StringProtocol>(_ title: S, sharedIcon: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, sharedIcon: sharedIcon) }
    }
}
