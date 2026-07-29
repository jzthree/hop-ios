import UIKit

// The hop keyboard (PLAN 21, Jian's ask): a full in-app keyboard that
// REPLACES the system one while the terminal is focused — UIResponder's
// inputView, the native mechanism, so toggling back is one assignment.
//
// Why it exists: a terminal wants what the system keyboard refuses to give —
// a FIXED height (no keyboard-switch resize lottery, the item-6 bug can't
// fire), no autocorrect bar appearing and vanishing, a mono face, and every
// ASCII symbol at most one plane away. The plane layout is the system's own
// three-plane scheme (abc / 123 / #+=) so the muscle memory transfers; the
// terminal keys (esc, tab, ctrl, arrows) stay on the accessory bar, which
// rides on top of any inputView automatically.
//
// The planes are DATA, and every printable ASCII character must be reachable
// — the unit suite proves it, because a terminal keyboard with an
// unreachable `|` or backtick is a desk you must walk back to.
enum HopBoardLayout {
    static let letters: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]
    static let numbers: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"]
    ]
    static let symbols: [[String]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "`", "'"],
        [".", ",", "?", "!", "\""]
    ]

    /// Every printable ASCII character the three planes can emit (letters
    /// counted in both cases via shift), plus the fixed keys.
    static var reachable: Set<Character> {
        var set = Set<Character>()
        for plane in [letters, numbers, symbols] {
            for row in plane {
                for key in row {
                    set.formUnion(key)
                    set.formUnion(key.uppercased())
                }
            }
        }
        set.insert(" ")
        return set
    }
}

/// The board itself. UIInputView so the system gives it the keyboard
/// background treatment; a fixed intrinsic height is the point.
final class HopBoardView: UIInputView {
    var onText: ((String) -> Void)?
    var onSystemKeyboard: (() -> Void)?

    static let boardHeight: CGFloat = 232

    private enum Plane { case letters, numbers, symbols }
    private var plane: Plane = .letters
    private var shifted = false
    private var repeatTimer: Timer?
    private let column = UIStackView()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.boardHeight),
                   inputViewStyle: .keyboard)
        translatesAutoresizingMaskIntoConstraints = false
        allowsSelfSizing = true
        column.axis = .vertical
        column.spacing = 7
        column.distribution = .fillEqually
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            column.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -4),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3)
        ])
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.boardHeight)
    }

    private func rebuild() {
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let rows: [[String]]
        switch plane {
        case .letters: rows = HopBoardLayout.letters
        case .numbers: rows = HopBoardLayout.numbers
        case .symbols: rows = HopBoardLayout.symbols
        }

        column.addArrangedSubview(charRow(rows[0], pad: 0))
        column.addArrangedSubview(charRow(rows[1], pad: plane == .letters ? 18 : 0))

        // Third row: a mode key, the plane's remaining characters, backspace.
        let third = UIStackView()
        third.axis = .horizontal
        third.spacing = 5
        switch plane {
        case .letters:
            third.addArrangedSubview(controlKey(shifted ? "⬆" : "⇧", spoken: "shift", width: 42) { [weak self] in
                guard let self else { return }
                self.shifted.toggle()
                self.rebuild()
            })
        case .numbers:
            third.addArrangedSubview(controlKey("#+=", spoken: "more symbols", width: 42) { [weak self] in
                self?.plane = .symbols; self?.rebuild()
            })
        case .symbols:
            third.addArrangedSubview(controlKey("123", spoken: "numbers", width: 42) { [weak self] in
                self?.plane = .numbers; self?.rebuild()
            })
        }
        let mid = charRow(rows[2], pad: 0)
        third.addArrangedSubview(mid)
        third.addArrangedSubview(repeatingBackspace())
        column.addArrangedSubview(third)

        // Bottom row: plane toggle, escape to the system keyboard, space,
        // return. The system-keyboard key is the dictation/emoji hatch.
        let bottom = UIStackView()
        bottom.axis = .horizontal
        bottom.spacing = 5
        let planeKey = plane == .letters
            ? controlKey("123", spoken: "numbers", width: 46) { [weak self] in
                self?.plane = .numbers; self?.rebuild()
            }
            : controlKey("abc", spoken: "letters", width: 46) { [weak self] in
                self?.plane = .letters; self?.shifted = false; self?.rebuild()
            }
        bottom.addArrangedSubview(planeKey)
        bottom.addArrangedSubview(controlKey("⌨", spoken: "system keyboard", width: 40) { [weak self] in
            self?.onSystemKeyboard?()
        })
        bottom.addArrangedSubview(key(" ", label: "space", spoken: "space", flexible: true))
        bottom.addArrangedSubview(key("\r", label: "⏎", spoken: "return", width: 64))
        column.addArrangedSubview(bottom)
    }

    private func charRow(_ chars: [String], pad: CGFloat) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
        row.distribution = .fillEqually
        row.isLayoutMarginsRelativeArrangement = pad > 0
        if pad > 0 { row.layoutMargins = UIEdgeInsets(top: 0, left: pad, bottom: 0, right: pad) }
        for ch in chars {
            let shown = shifted && plane == .letters ? ch.uppercased() : ch
            row.addArrangedSubview(key(shown, label: shown, spoken: shown))
        }
        return row
    }

    private func key(_ text: String, label: String, spoken: String,
                     width: CGFloat? = nil, flexible: Bool = false) -> UIButton {
        let btn = baseKey(label: label, spoken: spoken, prominent: false)
        btn.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onText?(text)
            UIDevice.current.playInputClick()
            // One-shot shift, like the system's: the cap applies to the next
            // letter only.
            if self.shifted, self.plane == .letters {
                self.shifted = false
                self.rebuild()
            }
        }, for: .touchUpInside)
        if let width { btn.widthAnchor.constraint(equalToConstant: width).isActive = true }
        if flexible { btn.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        return btn
    }

    private func controlKey(_ label: String, spoken: String, width: CGFloat,
                            action: @escaping () -> Void) -> UIButton {
        let btn = baseKey(label: label, spoken: spoken, prominent: true)
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        btn.widthAnchor.constraint(equalToConstant: width).isActive = true
        return btn
    }

    private func repeatingBackspace() -> UIButton {
        let btn = baseKey(label: "⌫", spoken: "backspace", prominent: true)
        btn.widthAnchor.constraint(equalToConstant: 42).isActive = true
        btn.addTarget(self, action: #selector(backspaceDown), for: .touchDown)
        for e: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit] {
            btn.addTarget(self, action: #selector(backspaceUp), for: e)
        }
        return btn
    }

    @objc private func backspaceDown() {
        onText?("\u{7f}")
        UIDevice.current.playInputClick()
        repeatTimer?.invalidate()
        // Same feel as the accessory bar's ⌫: a beat before repeat, then fast.
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onText?("\u{7f}") }
                }
            }
        }
    }

    @objc private func backspaceUp() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    private func baseKey(label: String, spoken: String, prominent: Bool) -> UIButton {
        var cfg = UIButton.Configuration.filled()
        cfg.title = label
        cfg.baseForegroundColor = .white
        cfg.background.backgroundColor = prominent
            ? UIColor(white: 1, alpha: 0.09) : .hopKey
        cfg.background.cornerRadius = 7
        cfg.background.strokeColor = UIColor(white: 1, alpha: 0.08)
        cfg.background.strokeWidth = 0.5
        cfg.contentInsets = .zero
        let font = UIFont.monospacedSystemFont(ofSize: label.count > 2 ? 13 : 17,
                                               weight: .regular)
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = font
            return out
        }
        let btn = UIButton(configuration: cfg)
        btn.accessibilityLabel = spoken
        btn.titleLabel?.lineBreakMode = .byClipping
        return btn
    }

    deinit {
        MainActor.assumeIsolated { repeatTimer?.invalidate() }
    }
}
