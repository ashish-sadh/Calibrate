import SwiftUI
import DriftCore
import UniformTypeIdentifiers

struct LabReportUploadView: View {
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingPDFPicker = false
    @State private var extractedResults: LabReportOCR.ExtractionOutput?
    @State private var reportDate = Date()
    @State private var labName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    uploadOptions
                    if isProcessing {
                        processingView
                    }
                    if let results = extractedResults {
                        previewSection(results)
                    }
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.surplus)
                            .multilineTextAlignment(.center)
                    }
                    privacyNote
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Upload Lab Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingPDFPicker,
                allowedContentTypes: [.pdf],
                onCompletion: handlePDFImport
            )
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: Theme.FontSize.display3))
                .foregroundStyle(Theme.accent)
            Text("Upload a Lab Report")
                .font(.headline)
            Text("Upload a PDF of your blood test results. Drift will automatically extract biomarker values.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var uploadOptions: some View {
        VStack(spacing: 10) {
            uploadButton(icon: "doc.fill", title: "Upload PDF", subtitle: "Quest, Labcorp, or any lab PDF") {
                showingPDFPicker = true
            }
        }
    }

    private func uploadButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .card()
    }

    private var processingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Theme.accent)
            Text("Extracting biomarkers...")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 20)
    }

    private func previewSection(_ output: LabReportOCR.ExtractionOutput) -> some View {
        let showAIWarning = output.isLLMParsed || output.results.contains(where: \.isAIParsed)
        return VStack(spacing: 14) {
            // Extracted count
            VStack(spacing: 4) {
                Text("\(output.results.count)")
                    .font(.system(size: Theme.FontSize.display1, weight: .bold, design: .rounded))
                Text("biomarkers extracted")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Accuracy warning — shown whenever Gemma was involved in parsing (not just per-result AI)
            if showAIWarning {
                aiAccuracyWarning
            }

            // Date picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Report Date")
                    .font(.subheadline.weight(.medium))
                DatePicker("", selection: $reportDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .colorScheme(.dark)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            // Lab name
            if let detected = output.labName {
                HStack {
                    Text("Lab: \(detected)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .card()
            }

            // Preview of extracted markers
            VStack(alignment: .leading, spacing: 4) {
                Text("EXTRACTED BIOMARKERS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)

                ForEach(output.results.prefix(10), id: \.biomarkerId) { result in
                    HStack {
                        Text(BiomarkerKnowledgeBase.byId[result.biomarkerId]?.name ?? result.biomarkerId)
                            .font(.caption)
                        if result.isAIParsed {
                            Image(systemName: "cpu")
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.surplus.opacity(0.8))
                        }
                        Spacer()
                        Text(formatValue(result.value))
                            .font(.caption.weight(.bold).monospacedDigit())
                        Text(result.unit)
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.vertical, 2)
                }

                if output.results.count > 10 {
                    Text("+ \(output.results.count - 10) more...")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .card()

            // Save button
            Button {
                saveReport(output)
            } label: {
                Text("Save Report")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
                    .foregroundStyle(.white)
            }
        }
    }

    private var aiAccuracyWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.surplus)
                .font(.subheadline)
            Text("Some values were extracted by AI. Verify against your original report before saving.")
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surplus.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusChip))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusChip).stroke(Theme.surplus.opacity(0.3), lineWidth: 1))
    }

    private var privacyNote: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Theme.deficit)
                    .font(.caption)
                Text("Your lab data is encrypted and private")
                    .font(.caption.weight(.medium))
            }
            Text("Lab reports are encrypted with AES-256 and stored locally on your device using iOS Data Protection. They never leave your phone. Drift does not collect, transmit, or share any of your health data.")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    // MARK: - Import Handlers

    private func handlePDFImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                isProcessing = true
                errorMessage = nil
                do {
                    let output = try await LabReportOCR.extract(fromPDF: url)
                    if output.results.isEmpty {
                        errorMessage = "No biomarkers could be extracted from this PDF. Try a clearer scan or a different format."
                    } else {
                        extractedResults = output
                        if let date = output.reportDate {
                            let fmt = DateFormatter()
                            fmt.dateFormat = "yyyy-MM-dd"
                            if let d = fmt.date(from: date) { reportDate = d }
                        }
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
                isProcessing = false
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Save

    private func saveReport(_ output: LabReportOCR.ExtractionOutput) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateStr = fmt.string(from: reportDate)

        var report = LabReport(
            reportDate: dateStr,
            labName: output.labName ?? (labName.isEmpty ? nil : labName),
            fileName: "lab_report_\(dateStr)",
            markerCount: output.results.count
        )

        do {
            try BiomarkerService.saveLabReport(&report)
            guard let reportId = report.id else { return }

            let biomarkerResults = output.results.map { extracted in
                let normalized = BiomarkerKnowledgeBase.normalize(
                    biomarkerId: extracted.biomarkerId,
                    value: extracted.value,
                    fromUnit: extracted.unit
                )
                return BiomarkerResult(
                    reportId: reportId,
                    biomarkerId: extracted.biomarkerId,
                    value: extracted.value,
                    unit: extracted.unit,
                    normalizedValue: normalized.value,
                    normalizedUnit: normalized.unit,
                    referenceLow: extracted.referenceLow,
                    referenceHigh: extracted.referenceHigh,
                    confidence: extracted.confidence,
                    isAIParsed: extracted.isAIParsed
                )
            }

            try BiomarkerService.saveBiomarkerResults(biomarkerResults)
            Log.biomarkers.info("Saved report with \(biomarkerResults.count) biomarker results")

            onComplete()
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func formatValue(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

