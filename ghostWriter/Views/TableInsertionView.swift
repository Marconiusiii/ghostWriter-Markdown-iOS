//
//  TableInsertionView.swift
//  ghostWriter
//
//  A short, linear form for choosing a Markdown table's dimensions.
//

import SwiftUI

struct TableInsertionView: View {
    let onInsert: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var columns = 2
    @State private var rows = 3

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Insert Table")
                        .font(.title)
                        .accessibilityAddTraits(.isHeader)

                    Text(
                        "Choose how many columns and rows you want. "
                        + "The first row will name the columns."
                    )
                }

                Section {
                    Picker("Columns", selection: $columns) {
                        ForEach(1...12, id: \.self) { value in
                            Text(value == 1 ? "1 column" : "\(value) columns")
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)

                    Picker("Rows", selection: $rows) {
                        ForEach(2...20, id: \.self) { value in
                            Text("\(value) rows")
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                }

                Section {
                    Button("Insert Table") {
                        onInsert(columns, rows)
                        dismiss()
                    }

                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
            }
        }
    }
}
