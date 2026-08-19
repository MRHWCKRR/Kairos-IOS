//
//  ScheduleView.swift
//  Kairos
//
//  Created by Yunfei Na on 19/8/2026.
//

import SwiftUI

struct ScheduleView: View {
    @Environment(StudyPlanRepository.self) private var planRepo

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Schedule")
                    .font(.headline)
                Text("Coming soon — this will show your scheduled events once the format is finalized.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Schedule")
        }
    }
}

#Preview {
    ScheduleView()
        .environment(StudyPlanRepository())
}
