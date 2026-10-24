import AppKit

/// Native notices must remeasure at the same actual width as hosted provider cards.
final class WrappedSecondaryMenuTextView: NSView, MenuCardMeasuring {
    private let textField: NSTextField
    private var measuredSize: NSSize?
    var needsWidthRemeasurement: Bool {
        self.measuredSize == nil
    }

    init(text: String) {
        self.textField = NSTextField(wrappingLabelWithString: text)
        self.textField.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        self.textField.textColor = .secondaryLabelColor
        self.textField.lineBreakMode = .byWordWrapping
        self.textField.maximumNumberOfLines = 0
        super.init(frame: .zero)
        self.addSubview(self.textField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: self.frame.width,
            height: self.measuredSize?.height ?? self.measuredHeight(width: self.frame.width))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - self.frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            self.measuredSize = nil
            self.invalidateIntrinsicContentSize()
        }
    }

    override func layout() {
        super.layout()
        self.textField.frame = NSRect(
            x: 18, y: 2, width: max(1, self.bounds.width - 28), height: max(1, self.bounds.height - 4))
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        let contentWidth = max(1, width - 28)
        self.textField.preferredMaxLayoutWidth = contentWidth
        let size = self.textField.cell?.cellSize(forBounds: NSRect(
            x: 0, y: 0, width: contentWidth, height: .greatestFiniteMagnitude)) ?? .zero
        return max(1, ceil(size.height + 4))
    }

    func applyMeasuredSize(width: CGFloat, height: CGFloat) {
        self.setFrameSize(NSSize(width: width, height: height))
        self.measuredSize = self.frame.size
        self.invalidateIntrinsicContentSize()
        self.needsLayout = true
    }
}

extension StatusItemController {
    func makeWrappedSecondaryTextItem(text: String, width: CGFloat) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let view = WrappedSecondaryMenuTextView(text: text)
        view.applyMeasuredSize(width: width, height: view.measuredHeight(width: width))
        item.view = view
        item.isEnabled = false
        item.toolTip = text
        return item
    }
}
