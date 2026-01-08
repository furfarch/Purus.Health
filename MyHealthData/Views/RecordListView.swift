import SwiftUI
import SwiftData

struct RecordListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MedicalRecord.updatedAt, order: .reverse) private var records: [MedicalRecord]

    @State private var selection: MedicalRecord?
    @State private var showingNewRecordType = false
    @State private var showingAbout = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(records) { record in
                    NavigationLink(value: record) {
                        HStack {
                            Image(systemName: record.isPet ? "cat" : "person")
                                .foregroundStyle(.secondary)
                                .imageScale(.large)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(displayName(for: record)).font(.headline)
                                Text("Updated \(record.updatedAt, format: .dateTime.year().month().day().hour().minute())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteRecords)
            }
            .navigationTitle("My Health Data")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }

                ToolbarItem {
                    Button {
                        showingNewRecordType = true
                    } label: {
                        Label("New Record", systemImage: "plus")
                    }
                }
            }
        } detail: {
            NavigationStack {
                if let selection {
                    RecordEditorView(record: selection)
                } else {
                    Text("Select a record")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .confirmationDialog("Create New Record", isPresented: $showingNewRecordType, titleVisibility: .visible) {
            Button {
                addRecord(isPet: false)
            } label: {
                Label("Human", systemImage: "person")
            }

            Button {
                addRecord(isPet: true)
            } label: {
                Label("Pet", systemImage: "cat")
            }

            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showingAbout) {
            VStack(spacing: 12) {
                Image(systemName: "app.fill")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .padding(.top, 20)

                Text("MyHealthData")
                    .font(.title2)
                    .bold()

                // Build date: use current date formatted yyyy-MM (approximate build date)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM"
                Text("Build: \(formatter.string(from: Date()))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("by furfarch")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
                Button("Done") { showingAbout = false }
                    .padding(.bottom, 20)
            }
            .frame(minWidth: 300, minHeight: 260)
            .padding()
        }
    }

    private func displayName(for record: MedicalRecord) -> String {
        return record.displayName
    }

    private func addRecord(isPet: Bool) {
        withAnimation {
            let record = MedicalRecord()
            record.updatedAt = Date()
            record.isPet = isPet
            modelContext.insert(record)
            selection = record
        }
    }

    private func deleteRecords(offsets: IndexSet) {
        withAnimation {
            let deleting = offsets.map { records[$0] }
            for record in deleting {
                modelContext.delete(record)
            }
            if let selection, deleting.contains(where: { $0 == selection }) {
                self.selection = nil
            }
        }
    }
}
