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
                    Stepper(
                        "Columns: \(columns)",
                        value: $columns,
                        in: 1...12
                    )

                    Stepper(
                        "Rows: \(rows)",
                        value: $rows,
                        in: 2...20
                    )
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
