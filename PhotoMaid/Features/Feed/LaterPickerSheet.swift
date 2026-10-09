import PhotoMaidCore
import SwiftUI

enum LaterPickerResult: Equatable {
    case day(LocalDay)
    case noDate
    /// Abbrechen, Wegwischen: nichts ändern (keine Entscheidung, kein Termin).
    case cancelled
}

/// Drehrad „In [n] [Tagen | Wochen | Monaten]“ wie beim Timer, wahlweise ein Datum im Kalender.
struct LaterPickerSheet: View {
    let initial: LaterInterval
    let today: LocalDay
    let allowsNoDate: Bool
    let finish: (LaterPickerResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: Int
    @State private var unit: LaterInterval.Unit
    @State private var useDate = false
    @State private var date: Date
    @State private var finished = false

    init(initial: LaterInterval, today: LocalDay, allowsNoDate: Bool, finish: @escaping (LaterPickerResult) -> Void) {
        self.initial = initial
        self.today = today
        self.allowsNoDate = allowsNoDate
        self.finish = finish
        _value = State(initialValue: initial.value)
        _unit = State(initialValue: initial.unit)
        _date = State(initialValue: today.adding(days: 14).startOfDay(in: .autoupdatingCurrent))
    }

    private var result: LocalDay {
        useDate ? LocalDay(date, timeZone: .autoupdatingCurrent) : LaterInterval(value: value, unit: unit).dueDay(from: today)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.m) {
                    if useDate {
                        DatePicker(L("change_date"), selection: $date,
                                   in: today.startOfDay(in: .autoupdatingCurrent)..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                    } else {
                        HStack(spacing: 0) {
                            Picker(L("picker_count"), selection: $value) {
                                ForEach(Array(LaterInterval.range(for: unit)), id: \.self) { n in
                                    Text(verbatim: CountText.number(n)).tag(n)
                                }
                            }
                            .pickerStyle(.wheel)
                            Picker(L("picker_unit"), selection: $unit) {
                                ForEach(LaterInterval.Unit.allCases, id: \.self) { u in
                                    Text(verbatim: LaterText.unit(u, value)).tag(u)
                                }
                            }
                            .pickerStyle(.wheel)
                        }
                        .onChange(of: unit) { _, u in value = min(value, LaterInterval.range(for: u).upperBound) }
                    }
                    Text(verbatim: L("picker_show_on", DayText.string(result)))
                        .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                    SecondaryButton(title: L(useDate ? "picker_choose_interval" : "picker_specific_date")) { useDate.toggle() }
                    if allowsNoDate {
                        Button { done(.noDate) } label: { Text(key: "picker_no_date").multilineTextAlignment(.center) }
                            .frame(minHeight: AppSpacing.minTouch)
                        Text(key: "picker_no_date_hint").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(AppSpacing.pageMargin)
            }
            .navigationTitle(L("later"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { done(.cancelled) } }
                ToolbarItem(placement: .confirmationAction) { Button(L("done")) { done(.day(result)) }.fontWeight(.semibold) }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { if !finished { finished = true; finish(.cancelled) } }
    }

    private func done(_ r: LaterPickerResult) {
        guard !finished else { return }
        finished = true
        finish(r)
        dismiss()
    }
}
