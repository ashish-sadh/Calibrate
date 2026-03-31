import SwiftUI
import AVFoundation
import PhotosUI

// MARK: - Camera Barcode Scanner

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onBarcodeFound: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController { let vc = ScannerViewController(); vc.onBarcodeFound = onBarcodeFound; return vc }
    func updateUIViewController(_ vc: ScannerViewController, context: Context) {}

    class ScannerViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
        var onBarcodeFound: ((String) -> Void)?
        private var captureSession: AVCaptureSession?
        private var hasFoundBarcode = false

        override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .black; setupCamera() }

        private func setupCamera() {
            let session = AVCaptureSession()
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.ean13, .ean8, .upce, .code128, .code39, .code93]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            addOverlay()
            captureSession = session
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        }

        private func addOverlay() {
            let overlay = UIView(frame: view.bounds)
            overlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            overlay.isUserInteractionEnabled = false
            view.addSubview(overlay)
            let scanArea = CGRect(x: view.bounds.width * 0.1, y: view.bounds.height * 0.3, width: view.bounds.width * 0.8, height: view.bounds.height * 0.15)
            let path = UIBezierPath(rect: overlay.bounds)
            path.append(UIBezierPath(roundedRect: scanArea, cornerRadius: 12).reversing())
            let mask = CAShapeLayer(); mask.path = path.cgPath; overlay.layer.mask = mask
            let border = CAShapeLayer(); border.path = UIBezierPath(roundedRect: scanArea, cornerRadius: 12).cgPath
            border.strokeColor = UIColor.white.withAlphaComponent(0.6).cgColor; border.fillColor = UIColor.clear.cgColor; border.lineWidth = 2
            view.layer.addSublayer(border)
            let label = UILabel(); label.text = "Point camera at barcode"; label.textColor = .white; label.font = .systemFont(ofSize: 14, weight: .medium)
            label.textAlignment = .center; label.frame = CGRect(x: 0, y: scanArea.maxY + 16, width: view.bounds.width, height: 20)
            view.addSubview(label)
        }

        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews() }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); captureSession?.stopRunning() }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !hasFoundBarcode, let obj = objects.first as? AVMetadataMachineReadableCodeObject, let barcode = obj.stringValue else { return }
            hasFoundBarcode = true; AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate)); captureSession?.stopRunning()
            onBarcodeFound?(barcode)
        }
    }
}

// MARK: - Main Barcode Lookup View

struct BarcodeLookupView: View {
    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var scannedBarcode: String?
    @State private var product: OpenFoodFactsService.Product?
    @State private var isLooking = false
    @State private var error: String?
    @State private var servings: Double = 1.0
    // OCR states
    @State private var showingCamera = false
    @State private var ocrResult: NutritionLabelOCR.ExtractedNutrition?
    @State private var isProcessingOCR = false

    var body: some View {
        NavigationStack {
            ZStack {
                if product == nil && ocrResult == nil && !isLooking && !isProcessingOCR && error == nil {
                    BarcodeScannerView { barcode in
                        scannedBarcode = barcode
                        lookupBarcode(barcode)
                    }
                    .ignoresSafeArea()
                } else if isLooking {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Looking up barcode...").font(.subheadline).foregroundStyle(.secondary)
                        if let b = scannedBarcode { Text(b).font(.caption.monospacedDigit()).foregroundStyle(.tertiary) }
                    }
                } else if isProcessingOCR {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Reading nutrition label...").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if let product {
                    productView(product)
                } else if ocrResult != nil {
                    ocrEditView
                }

                if let error, ocrResult == nil, product == nil {
                    notFoundView
                }
            }
            .navigationTitle("Scan Barcode").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fullScreenCover(isPresented: $showingCamera) {
                NutritionPhotoCaptureView { image in
                    processNutritionPhoto(image)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Not Found → Photo option

    private var notFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 40)).foregroundStyle(Theme.surplus)
            Text(error ?? "Product not found").font(.subheadline).foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo of Nutrition Label", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)

                Button("Scan Again") {
                    self.error = nil; product = nil; scannedBarcode = nil; ocrResult = nil
                }
                .buttonStyle(.bordered)

                Button("Enter Manually") {
                    // Pre-fill OCR result with zeros for manual entry
                    ocrResult = NutritionLabelOCR.ExtractedNutrition()
                    error = nil
                }
                .font(.caption).foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - OCR Edit View (editable fields)

    @State private var editName = ""
    @State private var editCalories = ""
    @State private var editProtein = ""
    @State private var editCarbs = ""
    @State private var editFat = ""
    @State private var editFiber = ""

    private var ocrEditView: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "doc.text.viewfinder").foregroundStyle(Theme.accent)
                        Text("Nutrition Label Scan").font(.subheadline.weight(.semibold))
                    }
                    Text("Review and edit the values below. OCR may not be perfect.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                VStack(spacing: 10) {
                    editField("Name", text: $editName, keyboard: .default)
                    editField("Calories", text: $editCalories, keyboard: .decimalPad)
                    editField("Protein (g)", text: $editProtein, keyboard: .decimalPad)
                    editField("Carbs (g)", text: $editCarbs, keyboard: .decimalPad)
                    editField("Fat (g)", text: $editFat, keyboard: .decimalPad)
                    editField("Fiber (g)", text: $editFiber, keyboard: .decimalPad)
                }
                .card()

                Button {
                    logOCRResult()
                } label: {
                    Label("Log Food", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)

                Button("Retake Photo") {
                    showingCamera = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Theme.background)
        .onAppear { populateOCRFields() }
    }

    private func editField(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label).font(.subheadline).frame(width: 90, alignment: .leading)
            TextField("0", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.monospacedDigit())
        }
    }

    private func populateOCRFields() {
        guard let ocr = ocrResult else { return }
        editName = ocr.name.isEmpty ? (scannedBarcode.map { "Barcode \($0)" } ?? "Scanned Food") : ocr.name
        editCalories = ocr.calories > 0 ? String(Int(ocr.calories)) : ""
        editProtein = ocr.proteinG > 0 ? String(format: "%.1f", ocr.proteinG) : ""
        editCarbs = ocr.carbsG > 0 ? String(format: "%.1f", ocr.carbsG) : ""
        editFat = ocr.fatG > 0 ? String(format: "%.1f", ocr.fatG) : ""
        editFiber = ocr.fiberG > 0 ? String(format: "%.1f", ocr.fiberG) : ""
    }

    private func logOCRResult() {
        var food = Food(
            name: editName.isEmpty ? "Scanned Food" : editName,
            category: "Scanned",
            servingSize: 100, servingUnit: "g",
            calories: Double(editCalories) ?? 0,
            proteinG: Double(editProtein) ?? 0,
            carbsG: Double(editCarbs) ?? 0,
            fatG: Double(editFat) ?? 0,
            fiberG: Double(editFiber) ?? 0
        )
        // Save to food DB so it shows up in future searches
        try? AppDatabase.shared.saveScannedFood(&food)
        viewModel.logFood(food, servings: servings, mealType: viewModel.autoMealType)
        dismiss()
    }

    // MARK: - Product View (from barcode lookup)

    private func productView(_ p: OpenFoodFactsService.Product) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name).font(.headline)
                    if let brand = p.brand { Text(brand).font(.subheadline).foregroundStyle(.secondary) }
                    Text("Per 100g").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()

                HStack(spacing: 8) {
                    mpill("\(Int(p.calories))", label: "cal", color: Theme.calorieBlue)
                    mpill("\(Int(p.proteinG))g", label: "P", color: Theme.proteinRed)
                    mpill("\(Int(p.carbsG))g", label: "C", color: Theme.carbsGreen)
                    mpill("\(Int(p.fatG))g", label: "F", color: Theme.fatYellow)
                    mpill("\(Int(p.fiberG))g", label: "Fiber", color: Theme.fiberBrown)
                }

                VStack(spacing: 10) {
                    HStack {
                        Text("Servings (100g each)"); Spacer()
                        TextField("1", value: $servings, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60)
                        Stepper("", value: $servings, in: 0.25...10, step: 0.25).frame(width: 100)
                    }
                    if let g = p.servingSizeG {
                        Button("Use serving size (\(Int(g))g)") { servings = g / 100.0 }
                            .font(.caption).foregroundStyle(Theme.accent)
                    }
                }.card()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Total").font(.caption).foregroundStyle(.secondary)
                    Text("\(Int(p.calories * servings))cal · \(Int(p.proteinG * servings))P \(Int(p.carbsG * servings))C \(Int(p.fatG * servings))F")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()

                Button { logProduct(p) } label: {
                    Label("Log Food", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(Theme.accent)

                Button("Scan Another") { product = nil; scannedBarcode = nil; error = nil }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Theme.background)
    }

    private func mpill(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6).background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func lookupBarcode(_ barcode: String) {
        guard !isLooking else { return }
        isLooking = true; error = nil
        Task {
            // Check local cache first
            if let cached = try? AppDatabase.shared.fetchCachedBarcode(barcode) {
                Log.foodLog.info("Barcode cache hit: \(cached.name)")
                product = OpenFoodFactsService.Product(
                    barcode: cached.barcode, name: cached.name, brand: cached.brand,
                    servingSize: cached.servingDescription, calories: cached.caloriesPer100g,
                    proteinG: cached.proteinGPer100g, carbsG: cached.carbsGPer100g,
                    fatG: cached.fatGPer100g, fiberG: cached.fiberGPer100g,
                    servingSizeG: cached.servingSizeG
                )
                isLooking = false
                return
            }

            // Fetch from Open Food Facts
            do {
                let p = try await OpenFoodFactsService.lookup(barcode: barcode)
                product = p
                // Cache locally for next time
                try? AppDatabase.shared.cacheBarcodeProduct(BarcodeCache(from: p))
                Log.foodLog.info("Barcode cached: \(p.name)")
            } catch {
                self.error = error.localizedDescription
            }
            isLooking = false
        }
    }

    private func logProduct(_ p: OpenFoodFactsService.Product) {
        var food = Food(name: [p.name, p.brand].compactMap { $0 }.joined(separator: " - "), category: "Scanned",
                        servingSize: p.servingSizeG ?? 100, servingUnit: "g",
                        calories: p.calories, proteinG: p.proteinG, carbsG: p.carbsG, fatG: p.fatG, fiberG: p.fiberG)
        // Save to food DB so it shows up in future searches
        try? AppDatabase.shared.saveScannedFood(&food)
        viewModel.logFood(food, servings: servings, mealType: viewModel.autoMealType)
        dismiss()
    }

    private func processNutritionPhoto(_ image: UIImage) {
        isProcessingOCR = true; error = nil
        Task {
            do {
                ocrResult = try await NutritionLabelOCR.extract(from: image)
                populateOCRFields()
            } catch {
                self.error = "Could not read nutrition label: \(error.localizedDescription)"
            }
            isProcessingOCR = false
        }
    }
}

// MARK: - Photo Capture View (Camera + Library)

struct NutritionPhotoCaptureView: View {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 60)).foregroundStyle(Theme.accent.opacity(0.5))
                Text("Capture the nutrition label")
                    .font(.subheadline).foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)

                    Button {
                        showingLibrary = true
                    } label: {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("Nutrition Label").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView { image in
                    onCapture(image)
                    dismiss()
                }
            }
            .photosPicker(isPresented: $showingLibrary, selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        onCapture(image)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - UIImagePickerController Camera Wrapper

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
