import SwiftUI
import UIKit

/// Clearance for the floating pill tab bar, measured from the bottom
/// safe-area edge (UIKit stacks `additionalSafeAreaInsets` on top of the
/// system home-indicator inset). Pill ≈ 58pt tall + 6pt bottom padding +
/// breathing room.
enum FloatingTabBar {
    static let clearance: CGFloat = 78
}

/// Reserves space for the floating pill tab bar across an entire
/// NavigationStack — root AND pushed screens — by extending the enclosing
/// UINavigationController's safe area.
///
/// Why not `.safeAreaInset(edge: .bottom)`? Applied outside the stack, the
/// UIKit navigation controller re-derives safe areas from the window and the
/// inset never reaches scroll content (field report 2026-07-10: Food / Today /
/// Workout / Body-Composition last rows trapped under the pill — the per-page
/// insets from eb364ae3 were no-ops). Applied inside, it covers only that one
/// screen and every *pushed* screen regresses again. The navigation
/// controller is the one owner both root and pushed screens inherit from.
struct FloatingTabBarClearance: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Extender() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private final class Extender: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
        }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard let nav = navigationController,
                  nav.additionalSafeAreaInsets.bottom != FloatingTabBar.clearance else { return }
            nav.additionalSafeAreaInsets.bottom = FloatingTabBar.clearance
        }
    }
}

extension View {
    /// Apply INSIDE a tab's NavigationStack (on its root content) so every
    /// screen in that stack scrolls clear of the floating pill bar.
    func floatingTabBarClearance() -> some View {
        background(FloatingTabBarClearance().allowsHitTesting(false))
    }
}
