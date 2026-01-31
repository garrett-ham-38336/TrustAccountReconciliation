import SwiftUI
import CoreData

struct SyncHistorySection: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SyncLog.syncDate, ascending: false)],
        animation: .default
    )
    private var syncLogs: FetchedResults<SyncLog>

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Sync History")
                .font(.title2)
                .fontWeight(.bold)

            if syncLogs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Sync History")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Sync with Guesty to see history here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Date")
                            .frame(width: 150, alignment: .leading)
                        Text("Type")
                            .frame(width: 80, alignment: .leading)
                        Text("Created")
                            .frame(width: 70, alignment: .trailing)
                        Text("Updated")
                            .frame(width: 70, alignment: .trailing)
                        Text("Status")
                            .frame(width: 100, alignment: .leading)
                        Spacer()
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(syncLogs) { log in
                                SyncLogRow(log: log)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                }
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
        }
    }
}

struct SyncLogRow: View {
    let log: SyncLog

    var body: some View {
        HStack {
            Text(log.syncDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
                .frame(width: 150, alignment: .leading)

            Text(log.syncType ?? "full")
                .frame(width: 80, alignment: .leading)

            Text("\(log.recordsCreated)")
                .frame(width: 70, alignment: .trailing)

            Text("\(log.recordsUpdated)")
                .frame(width: 70, alignment: .trailing)

            HStack(spacing: 4) {
                Image(systemName: log.status == "success" ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(log.status == "success" ? .green : .red)
                Text(log.status ?? "unknown")
            }
            .frame(width: 100, alignment: .leading)

            Spacer()
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
