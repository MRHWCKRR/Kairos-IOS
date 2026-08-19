//
//  TasksView.swift
//  Kairos
//
//  Created by Yunfei Na on 19/8/2026.
//

import SwiftUI

struct TasksView: View {
    @Environment(StudyPlanRepository.self) private var planRepo

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if planRepo.isLoading {
                        ProgressView("Loading tasks…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if let plan = planRepo.currentPlan {
                        ForEach(plan.boards.filter { !$0.archived }) { board in
                            ForEach(board.sections.filter { !$0.archived }) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(section.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    ForEach(section.tasks.filter { !$0.archived }) { task in
                                        taskRow(task: task, boardID: board.id, sectionID: section.id)
                                    }
                                }
                                .padding(14)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tasks")
        }
    }

    private func taskRow(task: KairosTask, boardID: String, sectionID: String) -> some View {
        Button {
            Task {
                await planRepo.toggleTask(boardID: boardID, sectionID: sectionID, taskID: task.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.completed ? .purple : .secondary)

                Text(task.title)
                    .font(.body)
                    .foregroundStyle(task.completed ? .secondary : .primary)
                    .strikethrough(task.completed)

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No tasks yet")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

#Preview {
    TasksView()
        .environment(StudyPlanRepository())
}
