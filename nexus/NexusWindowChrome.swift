#if os(macOS)
    import AppKit
    import SwiftUI

    /// Extends the app's backdrop gradient behind the title bar so the traffic
    /// lights, sidebar toggle, and toolbar menus sit on the same surface as the
    /// rest of the window instead of a flat system-white bar.
    struct NexusWindowChromeConfigurator: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async {
                configure(view.window)
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            DispatchQueue.main.async {
                configure(nsView.window)
            }
        }

        private func configure(_ window: NSWindow?) {
            guard let window, window.styleMask.contains(.fullSizeContentView) == false else {
                return
            }

            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    extension View {
        func nexusSeamlessWindowChrome() -> some View {
            background(NexusWindowChromeConfigurator())
        }
    }
#endif
