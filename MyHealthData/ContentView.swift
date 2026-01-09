//
//  ContentView.swift
//  MyHealthData
//
//  Created by Chris Furfari on 05.01.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        RecordListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
