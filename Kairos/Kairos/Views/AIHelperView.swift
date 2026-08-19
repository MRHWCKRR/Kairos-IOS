//
//  AIHelperView.swift
//  Kairos
//
//  Created by Yunfei Na on 19/8/2026.
//

import SwiftUI

struct AIHelperView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(.purple)
                Text("AI Helper")
                    .font(.headline)
                Text("Coming soon — chat with Kairos AI to plan and adjust your schedule.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AI Helper")
        }
    }
}

#Preview {
    AIHelperView()
}
