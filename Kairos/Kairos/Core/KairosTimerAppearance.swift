public struct KairosTimerAppearance: Equatable {
    public let type: String
    public let theme: String
    public let border: String

    public init(type: String?, theme: String?, border: String?) {
        self.type = ["watch", "digital", "nuclear"].contains(type ?? "") ? type! : "digital"
        self.theme = ["violet", "cyan", "green", "amber", "rose"].contains(theme ?? "") ? theme! : "violet"
        self.border = ["none", "glow", "neon", "hazard"].contains(border ?? "") ? border! : "glow"
    }
}
