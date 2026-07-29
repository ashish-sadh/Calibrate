import SwiftUI
import DriftCore
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

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                setupCamera()
            case .notDetermined:
                // #943 audit: @Sendable — TCC calls back off-main; an
                // inferred-@MainActor literal asserts at closure entry.
                AVCaptureDevice.requestAccess(for: .video) { @Sendable [weak self] granted in
                    Task { @MainActor in if granted { self?.setupCamera() } }
                }
            case .denied, .restricted:
                break
            @unknown default:
                break
            }
        }

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
            path.append(UIBezierPath(roundedRect: scanArea, cornerRadius: Theme.radiusSmall).reversing())
            let mask = CAShapeLayer(); mask.path = path.cgPath; overlay.layer.mask = mask
            let border = CAShapeLayer(); border.path = UIBezierPath(roundedRect: scanArea, cornerRadius: Theme.radiusSmall).cgPath
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
    @State private var amount: String = "1"
    @State private var barcodeLogTime = Date()
    @State private var barcodeMealType: MealType = .snack
    @State private var barcodeMealResolved = false
    @State private var selectedUnitIndex: Int = 0
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
                    .onAppear { FeatureUsage.record(TelemetryEvent.barcodeUsed) }
                    .ignoresSafeArea()
                } else if isLooking {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Looking up barcode...").font(.subheadline).foregroundStyle(Theme.textSecondary)
                        if let b = scannedBarcode { Text(b).font(.caption.monospacedDigit()).foregroundStyle(Theme.textTertiary) }
                    }
                } else if isProcessingOCR {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Reading nutrition label...").font(.subheadline).foregroundStyle(Theme.textSecondary)
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
        // 2026-05-24 field bug: barcode result screen rendered as
        // white-on-white because this used to force .dark while the V7
        // Theme tokens (cardBackground = #FFFFFF, background = #EFEFF1)
        // are light. Letting the scheme follow the parent (V7 light)
        // restores text contrast on the result + edit views. The actual
        // camera scan UI underneath stays black because the camera
        // preview layer covers the chrome.
    }

    // MARK: - Not Found → Photo option

    private var notFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: Theme.FontSize.display2)).foregroundStyle(Theme.surplus)
            Text(error ?? "Product not found").font(.subheadline).foregroundStyle(Theme.textSecondary)

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
                        .font(.caption).foregroundStyle(Theme.textSecondary)
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
        // The label's macros are PER SERVING, so the stored serving size must
        // be the label's serving, not a hardcoded 100 g — saving "AG1: 50 cal"
        // as a 100 g serving made every later gram-based log 8× off (inverse
        // of the AG1 phantom-scoop bug; audit 2026-07-14). 100 g only when the
        // label's serving size can't be parsed.
        let labelServingG = OpenFoodFactsService.parseServingSize(ocrResult?.servingSize)
        var food = Food(
            name: editName.isEmpty ? "Scanned Food" : editName,
            category: "Scanned",
            servingSize: labelServingG ?? 100, servingUnit: "g",
            calories: Double(editCalories) ?? 0,
            proteinG: Double(editProtein) ?? 0,
            carbsG: Double(editCarbs) ?? 0,
            fatG: Double(editFat) ?? 0,
            fiberG: Double(editFiber) ?? 0
        )
        // Save to food DB so it shows up in future searches
        FoodService.persistScannedFood(&food)
        viewModel.logFood(food, servings: 1, mealType: viewModel.autoMealType)
        dismiss()
    }

    // MARK: - Product View (from barcode lookup)

    /// #1048: the scanned product as a `Food` (per-serving macros) — single source for the
    /// preview, the default-amount seed, and logging, so all three agree.
    private func productFood(_ p: OpenFoodFactsService.Product) -> Food {
        let servingG = (p.servingSizeG ?? 100) / Double(p.piecesPerServing ?? 1)
        return Food(name: [p.name, p.brand].compactMap { $0 }.joined(separator: " - "),
                    category: "Scanned", servingSize: servingG, servingUnit: "g",
                    calories: p.calories * servingG / 100,
                    proteinG: p.proteinG * servingG / 100,
                    carbsG: p.carbsG * servingG / 100,
                    fatG: p.fatG * servingG / 100,
                    fiberG: p.fiberG * servingG / 100,
                    packageSizeG: p.packageSizeG)
    }

    private func productView(_ p: OpenFoodFactsService.Product) -> some View {
        let servingG = (p.servingSizeG ?? 100) / Double(p.piecesPerServing ?? 1)
        let food = productFood(p)
        let units = FoodUnit.smartUnits(for: food)
        let safeIndex = min(selectedUnitIndex, max(units.count - 1, 0))
        let unit = units.isEmpty ? FoodUnit(label: "g", gramsEquivalent: 1) : units[safeIndex]
        let amountNum = Double(amount) ?? 0
        let totalGrams = amountNum * unit.gramsEquivalent
        let multiplier = servingG > 0 ? totalGrams / servingG : amountNum

        return ScrollView {
            VStack(spacing: 14) {
                // Product info
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name).font(.headline)
                    if let brand = p.brand { Text(brand).font(.subheadline).foregroundStyle(Theme.textSecondary) }
                    let perText = "\(Int(p.calories))cal · \(Int(p.proteinG))P \(Int(p.carbsG))C \(Int(p.fatG))F per 100g"
                    Text(perText).font(.caption).foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()

                // Shared serving input
                ServingInputView(amount: $amount, selectedUnitIndex: $selectedUnitIndex,
                                 units: units, servingSize: servingG)

                // Total nutrition (use food.* which is per-serving, not p.* which is per-100g)
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(food.calories * multiplier))")
                            .font(.system(size: Theme.FontSize.display1, weight: .bold).monospacedDigit())
                        Text("cal").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    HStack(spacing: 12) {
                        mpill("\(Int(food.proteinG * multiplier))g", label: "P", color: Theme.proteinRed)
                        mpill("\(Int(food.carbsG * multiplier))g", label: "C", color: Theme.carbsGreen)
                        mpill("\(Int(food.fatG * multiplier))g", label: "F", color: Theme.fatYellow)
                        mpill("\(MacroFormatter.fiber(food.fiberG * multiplier))g", label: "Fiber", color: Theme.fiberBrown)
                    }
                }.card()

                // Past-day target must be visible on the committing surface
                // itself (2026-07-09 field ask).
                if !viewModel.isToday {
                    PastDayLogBadge(date: viewModel.selectedDate)
                        .frame(maxWidth: .infinity)
                }

                MealTimePicker(time: $barcodeLogTime, mealType: $barcodeMealType)
                    .onAppear {
                        // Same one-shot default as FoodLogSheet — don't clobber
                        // a user-picked meal on body refreshes.
                        if !barcodeMealResolved {
                            barcodeMealType = MealType.resolve(now: Date(), recentEntries: viewModel.todayEntries)
                            barcodeMealResolved = true
                        }
                    }

                Button { logProduct(p) } label: {
                    Label("Log Food", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(Theme.accent)

                Button("Scan Another") { product = nil; scannedBarcode = nil; error = nil; ocrResult = nil; selectedUnitIndex = 0; amount = "1" }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Theme.background)
    }

    private func mpill(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6).background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func lookupBarcode(_ barcode: String) {
        guard !isLooking else { return }
        isLooking = true; error = nil
        Task {
            func present(_ p: OpenFoodFactsService.Product) {
                product = p
                // #1048: seed a realistic serving (defaultAmount), not a hardcoded "1", so an
                // ml-primary beverage doesn't preview/log ~0 cal (1 ml of a 330 ml can).
                amount = FoodUnit.defaultAmount(for: productFood(p)); selectedUnitIndex = 0
            }
            func cachedProduct(_ cached: BarcodeCache) -> OpenFoodFactsService.Product {
                OpenFoodFactsService.Product(
                    barcode: cached.barcode, name: cached.name, brand: cached.brand,
                    servingSize: cached.servingDescription, calories: cached.caloriesPer100g,
                    proteinG: cached.proteinGPer100g, carbsG: cached.carbsGPer100g,
                    fatG: cached.fatGPer100g, fiberG: cached.fiberGPer100g,
                    servingSizeG: cached.servingSizeG,
                    piecesPerServing: OpenFoodFactsService.parsePieceCount(cached.servingDescription),
                    ingredientsText: nil,
                    novaGroup: nil,
                    // 0 = "checked, OFF has none" sentinel → no package unit
                    packageSizeG: cached.packageSizeG.flatMap { $0 >= 10 ? $0 : nil }
                )
            }

            // Local cache first. A NULL packageSizeG means the row predates the
            // v45 package-size column — the package was never looked up, so
            // fall through to a fresh fetch (the stale row still serves as the
            // offline fallback below). 0 means "checked, product has none".
            let cached = FoodService.fetchCachedBarcode(barcode)
            if let cached, cached.packageSizeG != nil {
                Log.foodLog.info("Barcode cache hit: \(cached.name)")
                present(cachedProduct(cached))
                isLooking = false
                return
            }

            // Fetch from Open Food Facts
            do {
                let p = try await OpenFoodFactsService.lookup(barcode: barcode)
                present(p)
                // Cache locally for next time
                FoodService.cacheBarcodeProduct(BarcodeCache(from: p))
                Log.foodLog.info("Barcode cached: \(p.name)")
            } catch {
                if let cached {
                    Log.foodLog.info("Barcode refresh failed, serving pre-v45 cache: \(cached.name)")
                    present(cachedProduct(cached))
                } else {
                    self.error = error.localizedDescription
                }
            }
            isLooking = false
        }
    }

    private func logProduct(_ p: OpenFoodFactsService.Product) {
        let servingG = (p.servingSizeG ?? 100) / Double(p.piecesPerServing ?? 1)
        // Create food with actual serving size (not hardcoded 100g)
        // Macros stored per-serving (scaled from per-100g)
        // Parse ingredients from OpenFoodFacts (comma-separated text → JSON array)
        let ingredientsJson: String? = p.ingredientsText.flatMap { text in
            let names = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
            return names.isEmpty ? nil : (try? JSONEncoder().encode(names)).flatMap { String(data: $0, encoding: .utf8) }
        }
        var food = Food(name: [p.name, p.brand].compactMap { $0 }.joined(separator: " - "), category: "Scanned",
                        servingSize: servingG, servingUnit: "g",
                        calories: p.calories * servingG / 100,
                        proteinG: p.proteinG * servingG / 100,
                        carbsG: p.carbsG * servingG / 100,
                        fatG: p.fatG * servingG / 100,
                        fiberG: p.fiberG * servingG / 100,
                        ingredients: ingredientsJson,
                        novaGroup: p.novaGroup,
                        packageSizeG: p.packageSizeG)
        FoodService.persistScannedFood(&food)
        // Calculate servings multiplier from amount + unit
        let units = FoodUnit.smartUnits(for: food)
        let safeIndex = min(selectedUnitIndex, max(units.count - 1, 0))
        let unit = units.isEmpty ? FoodUnit(label: "g", gramsEquivalent: 1) : units[safeIndex]
        let amountNum = Double(amount) ?? 1
        let totalGrams = amountNum * unit.gramsEquivalent
        let multiplier = servingG > 0 ? totalGrams / servingG : amountNum
        // Anchor the picker's time-of-day onto the viewed day (no-op for
        // today) — past-day logs must not carry a today timestamp.
        viewModel.logFood(food, servings: multiplier, mealType: barcodeMealType,
                          loggedAt: viewModel.anchoredToSelectedDay(barcodeLogTime))
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
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)

                VStack(spacing: 10) {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    // 2026-05-24 first-launch crash fix: PhotoLogCaptureView
                    // disables Take Photo when the camera isn't available
                    // (Simulator, hardware missing, perms denied). This sheet
                    // did not, so first-launch from the top-right Snap
                    // crashed the UIImagePickerController init.
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

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
        // 2026-05-24 field bug: barcode result screen rendered as
        // white-on-white because this used to force .dark while the V7
        // Theme tokens (cardBackground = #FFFFFF, background = #EFEFF1)
        // are light. Letting the scheme follow the parent (V7 light)
        // restores text contrast on the result + edit views. The actual
        // camera scan UI underneath stays black because the camera
        // preview layer covers the chrome.
    }
}

// MARK: - UIImagePickerController Camera Wrapper

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // Defensive: if the caller forgot to gate the button on
        // isSourceTypeAvailable(.camera), assigning .camera would crash.
        // Falls back to photo library — caller's onCapture still fires
        // with a chosen image.
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
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
