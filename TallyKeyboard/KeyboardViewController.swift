import UIKit

class KeyboardViewController: UIInputViewController {

    // MARK: - Config

    private static let appGroupID = "group.com.BlackBeansInc.Tally"
    private static let flushInterval: TimeInterval = 30
    private static let deleteRepeatInterval: TimeInterval = 0.1
    private static let doubleTapThreshold: TimeInterval = 0.3

    enum KeyboardLayoutMode { case letters, numbers, symbols, emoji }

    // MARK: - Layout state

    private var isShifted = false
    private var isCapsLock = false
    private var currentLayout: KeyboardLayoutMode = .letters
    private var lastShiftTapTime: Date?
    private var lastSpaceTapTime: Date?

    // MARK: - Capture state

    private var textBuffer = ""
    private var flushTimer: Timer?
    private let consentManager = ConsentManager()
    private let typingMetrics = TypingMetrics()
    private var deleteTimer: Timer?

    // MARK: - Views

    private let keysContainer = UIView()
    private var keyRows: [[(button: UIButton, type: KeyType)]] = []
    private var shiftButton: UIButton?
    private let collectionIndicator = UIView()
    private var heightConstraint: NSLayoutConstraint?

    // MARK: - Predictive suggestion bar

    private let suggestionBar = UIView()
    private var suggestionButtons: [UIButton] = []     // exactly 3 slots
    private var suggestionSeparators: [UIView] = []
    private var currentSuggestions: [String] = []
    private let textChecker = UITextChecker()
    private var suggestionBarHeight: CGFloat { isPad ? 48 : 42 }
    /// Vertical space the keys must leave at the top for the suggestion bar (none in emoji mode).
    private var keysTopInset: CGFloat { currentLayout == .emoji ? 0 : suggestionBarHeight }

    // Emoji page — a collection view (with cell reuse) keeps memory low enough for
    // the keyboard extension to hold the full emoji catalog without being jetsammed.
    private lazy var emojiCollection: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal     // iOS-style: swipe left through categories
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 8)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.alwaysBounceHorizontal = true
        cv.dataSource = self
        cv.delegate = self
        cv.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseID)
        return cv
    }()
    private let emojiBottomBar = UIView()
    private var emojiBarBuilt = false
    /// Sections shown in the emoji grid: an optional "Recent" section + the catalog categories.
    private var emojiModel: [(name: String, symbol: String, emojis: [String])] = []
    private var emojiTabButtons: [(button: UIButton, section: Int)] = []

    // MARK: - Swipe-to-type (glide) state

    private var words: [String] = []
    private var wordIndexByPair: [String: [Int]] = [:]   // "first+last letter" → word indices
    private var wordIndexByFirst: [Character: [Int]] = [:]
    private var letterCenters: [Character: CGPoint] = [:] // current layout's key centers
    private var glidePoints: [CGPoint] = []
    private var glideLetters: [Character] = []
    private var isGlide = false
    private var glideEndedAt: Date?
    private let glideTrail = CAShapeLayer()
    private let calloutView = UILabel()

    // MARK: - Convenience

    private var isPad: Bool { traitCollection.userInterfaceIdiom == .pad }
    private var isDarkMode: Bool { traitCollection.userInterfaceStyle == .dark }
    private var isLandscape: Bool { view.bounds.width > view.bounds.height && view.bounds.width > 500 }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContainers()
        setupSuggestionBar()
        setupGlide()
        rebuildKeys()
        updateModeVisibility()
        loadDictionary()
        // Build the (large) emoji catalog off the main thread so the first tap on the
        // emoji key is instant rather than hitching while ~1,600 glyphs are validated.
        DispatchQueue.global(qos: .utility).async { _ = KeyboardLayout.emojis }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateKeyboardHeight()
        startFlushTimer()
        updateCollectionIndicator()
        updateSuggestions()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        flushBuffer()
        flushTimer?.invalidate(); flushTimer = nil
        deleteTimer?.invalidate(); deleteTimer = nil
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateKeyboardHeight()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCurrentMode()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateCollectionIndicator()
        updateSuggestions()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous) {
            applyBackground()
            rebuildKeys()
            if emojiBarBuilt { rebuildEmojiTabBar() }
            emojiCollection.reloadData()
        }
    }

    // MARK: - Capture gating

    private var isSecureInput: Bool { textDocumentProxy.isSecureTextEntry ?? false }

    private var shouldCapture: Bool {
        guard !isSecureInput else { return false }       // never capture secure fields
        guard hasFullAccess else { return false }         // needs Full Access to write the buffer
        guard consentManager.isCollectionActive else { return false }
        guard consentManager.collectText else { return false }
        return true
    }

    /// Coarse, non-identifying field-type context — never the host app or its contents.
    private var inputContext: String {
        switch textDocumentProxy.keyboardType ?? .default {
        case .emailAddress: return "email"
        case .URL, .webSearch: return "url"
        case .numberPad, .numbersAndPunctuation, .decimalPad, .asciiCapableNumberPad: return "number"
        case .phonePad, .namePhonePad: return "phone"
        case .twitter: return "social"
        default: return "text"
        }
    }

    // MARK: - Buffer flush

    private func startFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: Self.flushInterval, repeats: true) { [weak self] _ in
            self?.flushBuffer()
        }
    }

    private func flushBuffer() {
        guard !textBuffer.isEmpty else { return }
        let text = textBuffer
        textBuffer = ""

        let appContext: String? = consentManager.collectInputContext ? inputContext : nil
        let wpm: Double? = consentManager.collectTypingMetadata ? typingMetrics.wpm : nil
        let backspaceRate: Double? = consentManager.collectTypingMetadata ? typingMetrics.backspaceRate : nil

        BufferDatabase().insertBatch(
            text: text,
            appContext: appContext,
            wpm: wpm,
            backspaceRate: backspaceRate,
            locale: Locale.current.identifier
        )
        typingMetrics.reset()
    }

    // MARK: - Containers

    private func setupContainers() {
        keysContainer.translatesAutoresizingMaskIntoConstraints = false
        emojiCollection.translatesAutoresizingMaskIntoConstraints = true
        emojiBottomBar.translatesAutoresizingMaskIntoConstraints = true

        view.addSubview(keysContainer)
        view.addSubview(emojiCollection)
        view.addSubview(emojiBottomBar)
        emojiCollection.isHidden = true
        emojiBottomBar.isHidden = true

        NSLayoutConstraint.activate([
            keysContainer.topAnchor.constraint(equalTo: view.topAnchor),
            keysContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keysContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keysContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Green recording dot — positioned on the space bar in layoutKeys().
        collectionIndicator.translatesAutoresizingMaskIntoConstraints = true
        collectionIndicator.layer.cornerRadius = 4
        collectionIndicator.backgroundColor = .systemGreen
        collectionIndicator.alpha = 0
        keysContainer.addSubview(collectionIndicator)

        applyBackground()
    }

    private func applyBackground() {
        let bg: UIColor = isDarkMode
            ? UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1.0)
            : UIColor(red: 0.82, green: 0.835, blue: 0.86, alpha: 1.0)
        view.backgroundColor = bg
        emojiBottomBar.backgroundColor = bg
    }

    private func updateKeyboardHeight() {
        let target = preferredKeyboardHeight
        if heightConstraint == nil {
            heightConstraint = view.heightAnchor.constraint(equalToConstant: target)
            heightConstraint?.priority = UILayoutPriority(999)
            heightConstraint?.isActive = true
        } else if heightConstraint?.constant != target {
            heightConstraint?.constant = target
        }
    }

    private var preferredKeyboardHeight: CGFloat {
        // Keys block + the predictive suggestion bar on top (constant height across modes;
        // the bar is simply hidden in emoji mode so the grid uses the freed space).
        let keys: CGFloat = isPad ? 300 : (isLandscape ? 162 : 216)
        return keys + suggestionBarHeight
    }

    // MARK: - Build keys

    private func rows(for mode: KeyboardLayoutMode) -> [[KeyType]] {
        switch mode {
        case .letters: return KeyboardLayout.letterRows
        case .numbers: return KeyboardLayout.numberRows
        case .symbols: return KeyboardLayout.symbolRows
        case .emoji: return []
        }
    }

    private func rebuildKeys() {
        keyRows.forEach { $0.forEach { $0.button.removeFromSuperview() } }
        keyRows.removeAll()
        shiftButton = nil

        for row in rows(for: currentLayout) {
            var built: [(UIButton, KeyType)] = []
            for key in row {
                let b = createKey(key)
                keysContainer.addSubview(b)
                built.append((b, key))
                if case .shift = key { shiftButton = b }
            }
            keyRows.append(built)
        }
        view.setNeedsLayout()
    }

    // MARK: - Layout (manual frames → fully responsive)

    private struct Metrics {
        let side: CGFloat, gap: CGFloat, vgap: CGFloat, top: CGFloat, bottom: CGFloat
        let rowWidth: CGFloat, unit: CGFloat, rowH: CGFloat
    }

    private func metrics(rowCount: Int) -> Metrics {
        let W = view.bounds.width
        let side: CGFloat = isPad ? 8 : 4
        let gap: CGFloat = isPad ? 10 : 6
        let vgap: CGFloat = isPad ? 12 : (isLandscape ? 8 : 11)
        // Keys start below the suggestion bar (keysTopInset is 0 in emoji mode).
        let top: CGFloat = keysTopInset + (isPad ? 8 : 6)
        // Small fixed bottom padding only — iOS owns the home-indicator region below us.
        let bottom: CGFloat = isPad ? 6 : 4
        let rowWidth = W - 2 * side
        let unit = (rowWidth - 9 * gap) / 10            // 10-column reference width
        let usableH = view.bounds.height - top - bottom
        let rowH = (usableH - CGFloat(rowCount - 1) * vgap) / CGFloat(rowCount)
        return Metrics(side: side, gap: gap, vgap: vgap, top: top, bottom: bottom,
                       rowWidth: rowWidth, unit: unit, rowH: rowH)
    }

    private func layoutCurrentMode() {
        layoutSuggestionBar()
        if currentLayout == .emoji {
            layoutEmoji()
        } else {
            layoutKeys()
        }
    }

    private func layoutKeys() {
        guard !keyRows.isEmpty else { return }
        let m = metrics(rowCount: keyRows.count)
        var y = m.top

        for (rowIndex, row) in keyRows.enumerated() {
            let widths = rowWidths(rowIndex: rowIndex, keys: row.map { $0.type }, m: m)
            let totalKeys = widths.reduce(0, +)
            let totalGaps = CGFloat(row.count - 1) * m.gap
            let used = totalKeys + totalGaps
            // Center rows that don't span the full width (e.g. the 9-key home row).
            var x = m.side + max(0, (m.rowWidth - used) / 2)
            for (i, item) in row.enumerated() {
                let w = widths[i]
                item.button.frame = CGRect(x: x, y: y, width: w, height: m.rowH).integral
                x += w + m.gap
            }
            y += m.rowH + m.vgap
        }
        updateLetterCenters()
        positionRecordingDot()
    }

    /// Places the green recording dot on the left of the space bar.
    private func positionRecordingDot() {
        var spaceFrame: CGRect?
        for row in keyRows where spaceFrame == nil {
            for item in row where item.type == .space { spaceFrame = item.button.frame }
        }
        guard let frame = spaceFrame else { collectionIndicator.isHidden = true; return }
        collectionIndicator.isHidden = false
        let size: CGFloat = 8
        collectionIndicator.frame = CGRect(x: frame.minX + 16, y: frame.midY - size / 2,
                                           width: size, height: size)
        keysContainer.bringSubviewToFront(collectionIndicator)
        updateCollectionIndicator()
    }

    /// Caches the on-screen center of each letter key for glide decoding & hit-testing.
    private func updateLetterCenters() {
        letterCenters.removeAll(keepingCapacity: true)
        guard currentLayout == .letters else { return }
        for row in keyRows {
            for item in row {
                if case .letter(let c) = item.type, c != "ABC", let ch = c.lowercased().first {
                    letterCenters[ch] = item.button.center
                }
            }
        }
    }

    /// Per-key widths for a row, sized to fill the keyboard authentically.
    private func rowWidths(rowIndex: Int, keys: [KeyType], m: Metrics) -> [CGFloat] {
        let u = m.unit
        let isBottom = keys.contains(.space)

        if isBottom {
            // [modeKey] [globe] [emoji] [space.....] [return]
            return keys.map { key in
                switch key {
                case .numbers, .symbols:        return u * 1.35
                case .letter("ABC"):            return u * 1.35
                case .globe, .emoji:            return u * 1.1
                case .return:                   return u * 2.0
                case .space:                    return -1            // placeholder, filled below
                default:                        return u
                }
            }.fillingSpace(rowWidth: m.rowWidth, gap: m.gap)
        }

        // Rows that have a wide modifier on each end (shift/delete, symbols/delete…).
        let endsAreModifiers: Bool = {
            guard let first = keys.first, let last = keys.last else { return false }
            return isModifier(first) && isModifier(last)
        }()

        if endsAreModifiers {
            let middleCount = keys.count - 2
            // Home-row letters keep the base unit width and the side keys fill the rest,
            // so the letters stay vertically aligned with the rows above (authentic).
            let lettersAreSingleUnit = keys.dropFirst().dropLast().allSatisfy {
                if case .letter = $0 { return true } else { return false }
            } && middleCount == 7
            if lettersAreSingleUnit {
                let sideW = (m.rowWidth - CGFloat(middleCount) * u - CGFloat(keys.count - 1) * m.gap) / 2
                return keys.enumerated().map { (i, _) in (i == 0 || i == keys.count - 1) ? sideW : u }
            } else {
                // Punctuation rows: ends slightly wide, middle keys share the remainder.
                let sideW = u * 1.3
                let midW = (m.rowWidth - 2 * sideW - CGFloat(keys.count - 1) * m.gap) / CGFloat(middleCount)
                return keys.enumerated().map { (i, _) in (i == 0 || i == keys.count - 1) ? sideW : midW }
            }
        }

        // Plain rows (10 across, or the centered 9-key home row): equal units.
        return keys.map { _ in u }
    }

    private func isModifier(_ key: KeyType) -> Bool {
        switch key {
        case .shift, .delete, .numbers, .symbols, .globe, .emoji, .return: return true
        case .letter("ABC"): return true
        default: return false
        }
    }

    // MARK: - Key creation & styling

    private func createKey(_ key: KeyType) -> UIButton {
        let b = UIButton(type: .custom)
        b.translatesAutoresizingMaskIntoConstraints = true
        b.layer.cornerRadius = isPad ? 6 : 5
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.5
        b.layer.shadowColor = UIColor.black.cgColor
        b.layer.shadowOffset = CGSize(width: 0, height: 1)
        b.layer.shadowOpacity = isDarkMode ? 0.45 : 0.28
        b.layer.shadowRadius = 0

        let letterFont = UIFont.systemFont(ofSize: isPad ? 25 : 22, weight: .regular)
        let modFont = UIFont.systemFont(ofSize: isPad ? 18 : 16, weight: .regular)

        switch key {
        case .letter(let char):
            if char == "ABC" {
                styleModifier(b); b.setTitle("ABC", for: .normal)
                b.titleLabel?.font = UIFont.systemFont(ofSize: isPad ? 17 : 15)
                b.addTarget(self, action: #selector(switchToLetters), for: .touchUpInside)
            } else {
                styleLetter(b)
                b.setTitle(displayCharacter(for: char), for: .normal)
                b.titleLabel?.font = letterFont
                b.accessibilityLabel = char
                b.addTarget(self, action: #selector(letterKeyPressed(_:)), for: .touchUpInside)
                b.addTarget(self, action: #selector(keyTouchDown(_:)), for: .touchDown)
                b.addTarget(self, action: #selector(keyTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchDragExit])
            }
        case .shift:
            styleModifier(b); b.titleLabel?.font = modFont
            updateShiftButtonTitle(b)
            b.addTarget(self, action: #selector(shiftKeyPressed(_:)), for: .touchUpInside)
        case .delete:
            styleModifier(b); b.setTitle("⌫", for: .normal); b.titleLabel?.font = modFont
            b.addTarget(self, action: #selector(deleteKeyPressed), for: .touchUpInside)
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(deleteLongPress(_:)))
            lp.minimumPressDuration = 0.3
            b.addGestureRecognizer(lp)
        case .numbers:
            styleModifier(b); b.setTitle("123", for: .normal)
            b.titleLabel?.font = UIFont.systemFont(ofSize: isPad ? 17 : 15)
            b.addTarget(self, action: #selector(switchToNumbers), for: .touchUpInside)
        case .symbols:
            styleModifier(b); b.setTitle("#+=", for: .normal)
            b.titleLabel?.font = UIFont.systemFont(ofSize: isPad ? 17 : 15)
            b.addTarget(self, action: #selector(switchToSymbols), for: .touchUpInside)
        case .space:
            styleLetter(b)
            // Faint "Tally" watermark instead of "space".
            b.setTitle("Tally", for: .normal)
            b.titleLabel?.font = UIFont.systemFont(ofSize: isPad ? 18 : 16, weight: .regular)
            b.setTitleColor((isDarkMode ? UIColor.white : UIColor.black).withAlphaComponent(0.22), for: .normal)
            b.addTarget(self, action: #selector(spaceKeyPressed), for: .touchUpInside)
        case .return:
            styleModifier(b); b.setTitle(returnKeyLabel, for: .normal); b.titleLabel?.font = modFont
            b.backgroundColor = UIColor(red: 0.13, green: 0.45, blue: 0.95, alpha: 1.0)
            b.setTitleColor(.white, for: .normal)
            b.addTarget(self, action: #selector(returnKeyPressed), for: .touchUpInside)
        case .globe:
            styleModifier(b); b.setImage(UIImage(systemName: "globe"), for: .normal)
            b.tintColor = isDarkMode ? .white : .black
            b.addTarget(self, action: #selector(globeKeyPressed), for: .touchUpInside)
        case .emoji:
            styleModifier(b); b.setImage(UIImage(systemName: "face.smiling"), for: .normal)
            b.tintColor = isDarkMode ? .white : .black
            b.addTarget(self, action: #selector(switchToEmoji), for: .touchUpInside)
        case .period:
            styleLetter(b); b.setTitle(".", for: .normal); b.titleLabel?.font = letterFont
            b.addTarget(self, action: #selector(periodKeyPressed), for: .touchUpInside)
        case .comma:
            styleLetter(b); b.setTitle(",", for: .normal); b.titleLabel?.font = letterFont
            b.addTarget(self, action: #selector(commaKeyPressed), for: .touchUpInside)
        }
        return b
    }

    private func styleLetter(_ b: UIButton) {
        b.backgroundColor = isDarkMode ? UIColor(white: 0.42, alpha: 1.0) : .white
        b.setTitleColor(isDarkMode ? .white : .black, for: .normal)
    }

    private func styleModifier(_ b: UIButton) {
        b.backgroundColor = isDarkMode ? UIColor(white: 0.27, alpha: 1.0)
                                       : UIColor(red: 0.68, green: 0.70, blue: 0.73, alpha: 1.0)
        b.setTitleColor(isDarkMode ? .white : .black, for: .normal)
    }

    private func displayCharacter(for char: String) -> String {
        if currentLayout == .letters && !isCapsLock && !isShifted { return char.lowercased() }
        return char
    }

    private var returnKeyLabel: String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return "Go"; case .google: return "Google"; case .join: return "Join"
        case .next: return "Next"; case .route: return "Route"; case .search: return "Search"
        case .send: return "Send"; case .yahoo: return "Yahoo"; case .done: return "Done"
        case .emergencyCall: return "Call"; case .continue: return "Continue"
        default: return "return"
        }
    }

    private func updateShiftButtonTitle(_ b: UIButton) {
        b.setImage(nil, for: .normal)
        if isCapsLock {
            b.setTitle("⇪", for: .normal)
            b.backgroundColor = .white; b.setTitleColor(.black, for: .normal)
        } else if isShifted {
            b.setTitle("⇧", for: .normal)
            b.backgroundColor = .white; b.setTitleColor(.black, for: .normal)
        } else {
            b.setTitle("⇧", for: .normal); styleModifier(b)
        }
    }

    // MARK: - Key actions

    @objc private func letterKeyPressed(_ sender: UIButton) {
        // Suppress the stray tap that can fire right after a glide ends on the same key.
        if let t = glideEndedAt, Date().timeIntervalSince(t) < 0.18 {
            glideEndedAt = nil
            return
        }
        guard let title = sender.accessibilityLabel ?? sender.title(for: .normal) else { return }
        let char: String
        if currentLayout == .letters {
            char = (isShifted || isCapsLock) ? title.uppercased() : title.lowercased()
        } else {
            char = title
        }
        textDocumentProxy.insertText(char)
        playClick()
        capture(char)
        if isShifted && !isCapsLock && currentLayout == .letters {
            isShifted = false
            refreshLetterCases()
        }
    }

    @objc private func shiftKeyPressed(_ sender: UIButton) {
        let now = Date()
        if let last = lastShiftTapTime, now.timeIntervalSince(last) < Self.doubleTapThreshold {
            isCapsLock = true; isShifted = true; lastShiftTapTime = nil
        } else {
            if isCapsLock { isCapsLock = false; isShifted = false }
            else { isShifted.toggle() }
            lastShiftTapTime = now
        }
        updateShiftButtonTitle(sender)
        refreshLetterCases()
        playClick()
    }

    @objc private func deleteKeyPressed() {
        textDocumentProxy.deleteBackward()
        playClick()
        if shouldCapture {
            if !textBuffer.isEmpty { textBuffer.removeLast() }
            typingMetrics.recordBackspace()
        }
    }

    @objc private func deleteLongPress(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            deleteTimer = Timer.scheduledTimer(withTimeInterval: Self.deleteRepeatInterval, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.textDocumentProxy.deleteBackward()
                if self.shouldCapture {
                    if !self.textBuffer.isEmpty { self.textBuffer.removeLast() }
                    self.typingMetrics.recordBackspace()
                }
            }
        case .ended, .cancelled, .failed:
            deleteTimer?.invalidate(); deleteTimer = nil
        default: break
        }
    }

    @objc private func spaceKeyPressed() {
        let now = Date()
        if let last = lastSpaceTapTime, now.timeIntervalSince(last) < Self.doubleTapThreshold {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
            if shouldCapture {
                if !textBuffer.isEmpty { textBuffer.removeLast() }
                textBuffer.append(". "); typingMetrics.recordKeystroke()
            }
            lastSpaceTapTime = nil
        } else {
            textDocumentProxy.insertText(" ")
            capture(" ")
            lastSpaceTapTime = now
        }
        playClick()
    }

    @objc private func returnKeyPressed() {
        textDocumentProxy.insertText("\n"); playClick(); capture("\n")
    }

    @objc private func globeKeyPressed() { advanceToNextInputMode() }
    @objc private func periodKeyPressed() { textDocumentProxy.insertText("."); playClick(); capture(".") }
    @objc private func commaKeyPressed() { textDocumentProxy.insertText(","); playClick(); capture(",") }

    @objc private func switchToNumbers() { currentLayout = .numbers; rebuildKeys(); updateModeVisibility() }
    @objc private func switchToSymbols() { currentLayout = .symbols; rebuildKeys(); updateModeVisibility() }
    @objc private func switchToLetters() {
        currentLayout = .letters; isShifted = false; isCapsLock = false
        rebuildKeys(); updateModeVisibility()
    }
    @objc private func switchToEmoji() {
        currentLayout = .emoji
        rebuildEmojiModel()
        buildEmojiTabBar()
        emojiCollection.reloadData()
        updateModeVisibility()
        view.setNeedsLayout()
        highlightEmojiTab(section: 0)
    }

    private func capture(_ s: String) {
        guard shouldCapture else { return }
        textBuffer.append(s)
        typingMetrics.recordKeystroke()
    }

    private func refreshLetterCases() {
        guard currentLayout == .letters else { return }
        for row in keyRows {
            for item in row {
                if case .letter(let c) = item.type, c != "ABC" {
                    item.button.setTitle(displayCharacter(for: c), for: .normal)
                }
            }
        }
    }

    // MARK: - Touch feedback

    @objc private func keyTouchDown(_ sender: UIButton) {
        if let ch = sender.title(for: .normal) { showCallout(for: sender, text: ch) }
        UIView.animate(withDuration: 0.04) {
            sender.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
            sender.alpha = 0.9
        }
    }
    @objc private func keyTouchUp(_ sender: UIButton) {
        hideCallout()
        UIView.animate(withDuration: 0.1) { sender.transform = .identity; sender.alpha = 1.0 }
    }
    private func playClick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Emoji page

    private func rebuildEmojiModel() {
        var model: [(name: String, symbol: String, emojis: [String])] = []
        let recents = loadRecentEmojis()
        if !recents.isEmpty { model.append(("Recent", "clock", recents)) }
        for c in EmojiCatalog.categories { model.append((c.name, c.symbol, c.emojis)) }
        emojiModel = model
    }

    /// Bottom tab bar: [ABC] · recents/category tabs · [⌫]
    private func buildEmojiTabBar() {
        emojiBarBuilt = true
        emojiBottomBar.subviews.forEach { $0.removeFromSuperview() }
        emojiTabButtons.removeAll()

        let abc = UIButton(type: .custom)
        styleModifier(abc); abc.setTitle("ABC", for: .normal)
        abc.titleLabel?.font = UIFont.systemFont(ofSize: isPad ? 17 : 15)
        abc.layer.cornerRadius = isPad ? 6 : 5
        abc.tag = 1001
        abc.addTarget(self, action: #selector(switchToLetters), for: .touchUpInside)
        emojiBottomBar.addSubview(abc)

        for (i, section) in emojiModel.enumerated() {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: section.symbol), for: .normal)
            b.tintColor = .secondaryLabel
            b.tag = 2000 + i
            b.addTarget(self, action: #selector(emojiTabTapped(_:)), for: .touchUpInside)
            emojiBottomBar.addSubview(b)
            emojiTabButtons.append((b, i))
        }

        let del = UIButton(type: .custom)
        styleModifier(del); del.setImage(UIImage(systemName: "delete.left"), for: .normal)
        del.tintColor = isDarkMode ? .white : .black
        del.layer.cornerRadius = isPad ? 6 : 5
        del.tag = 1002
        del.addTarget(self, action: #selector(deleteKeyPressed), for: .touchUpInside)
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(deleteLongPress(_:)))
        lp.minimumPressDuration = 0.3
        del.addGestureRecognizer(lp)
        emojiBottomBar.addSubview(del)
    }

    private func rebuildEmojiTabBar() {
        emojiBarBuilt = false
        buildEmojiTabBar()
    }

    /// Number of visible rows in the horizontally-scrolling grid.
    private var emojiRows: Int { isPad ? 7 : 5 }

    @objc private func emojiTabTapped(_ sender: UIButton) {
        let section = sender.tag - 2000
        guard section >= 0, section < emojiModel.count, !emojiModel[section].emojis.isEmpty else { return }
        emojiCollection.scrollToItem(at: IndexPath(item: 0, section: section), at: .left, animated: false)
        highlightEmojiTab(section: section)
    }

    private func highlightEmojiTab(section: Int) {
        for (button, s) in emojiTabButtons {
            button.tintColor = (s == section) ? .label : .secondaryLabel
        }
    }

    private func layoutEmoji() {
        let m = metrics(rowCount: 4)
        let barH = m.rowH + m.bottom

        emojiCollection.frame = CGRect(x: 0, y: 0, width: view.bounds.width,
                                       height: max(0, view.bounds.height - barH))
        emojiBottomBar.frame = CGRect(x: 0, y: view.bounds.height - barH,
                                      width: view.bounds.width, height: barH)
        emojiCollection.collectionViewLayout.invalidateLayout()

        // Lay out the tab bar: ABC | category tabs evenly spaced | ⌫
        let endW = m.unit * 1.5
        let rowH = max(m.rowH, 1)
        let by: CGFloat = (barH - m.bottom - rowH) / 2
        emojiBottomBar.viewWithTag(1001)?.frame = CGRect(x: m.side, y: by, width: endW, height: rowH)
        emojiBottomBar.viewWithTag(1002)?.frame =
            CGRect(x: view.bounds.width - m.side - endW, y: by, width: endW, height: rowH)

        let stripX = m.side + endW + m.gap
        let stripW = view.bounds.width - 2 * (m.side + endW + m.gap)
        let n = max(emojiTabButtons.count, 1)
        let tabW = stripW / CGFloat(n)
        for (button, i) in emojiTabButtons {
            button.frame = CGRect(x: stripX + CGFloat(i) * tabW, y: by, width: tabW, height: rowH)
        }
    }

    // MARK: - Recent emoji (shared via App Group)

    private func loadRecentEmojis() -> [String] {
        UserDefaults(suiteName: Self.appGroupID)?.stringArray(forKey: "emoji_recents") ?? []
    }

    private func recordRecentEmoji(_ emoji: String) {
        let defaults = UserDefaults(suiteName: Self.appGroupID)
        var arr = defaults?.stringArray(forKey: "emoji_recents") ?? []
        arr.removeAll { $0 == emoji }
        arr.insert(emoji, at: 0)
        if arr.count > 36 { arr = Array(arr.prefix(36)) }
        defaults?.set(arr, forKey: "emoji_recents")
    }

    private func updateModeVisibility() {
        let emoji = currentLayout == .emoji
        keysContainer.isHidden = emoji
        emojiCollection.isHidden = !emoji
        emojiBottomBar.isHidden = !emoji
    }

    // MARK: - Swipe-to-type (glide / QuickPath-style)

    private func setupGlide() {
        // Trail layer for the glide stroke.
        glideTrail.fillColor = nil
        glideTrail.strokeColor = UIColor.systemBlue.withAlphaComponent(0.55).cgColor
        glideTrail.lineWidth = 6
        glideTrail.lineCap = .round
        glideTrail.lineJoin = .round
        keysContainer.layer.addSublayer(glideTrail)

        // Key pop-up callout (the bubble shown above a pressed key).
        calloutView.textAlignment = .center
        calloutView.font = .systemFont(ofSize: 30, weight: .regular)
        calloutView.layer.cornerRadius = 8
        calloutView.layer.masksToBounds = false
        calloutView.layer.shadowColor = UIColor.black.cgColor
        calloutView.layer.shadowOpacity = 0.25
        calloutView.layer.shadowRadius = 3
        calloutView.layer.shadowOffset = CGSize(width: 0, height: 2)
        calloutView.isHidden = true
        view.addSubview(calloutView)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleGlide(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false   // let normal taps keep working
        pan.maximumNumberOfTouches = 1
        keysContainer.addGestureRecognizer(pan)
    }

    private func loadDictionary() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let url = Bundle.main.url(forResource: "words", withExtension: "txt"),
                  let content = try? String(contentsOf: url, encoding: .utf8) else {
                print("[Glide] words.txt not found in bundle")
                return
            }
            let list = content.split(whereSeparator: \.isNewline).map(String.init)
            var byPair: [String: [Int]] = [:]
            var byFirst: [Character: [Int]] = [:]
            for (i, w) in list.enumerated() {
                guard let f = w.first, let l = w.last else { continue }
                byPair["\(f)\(l)", default: []].append(i)
                byFirst[f, default: []].append(i)
            }
            DispatchQueue.main.async {
                self?.words = list
                self?.wordIndexByPair = byPair
                self?.wordIndexByFirst = byFirst
            }
        }
    }

    @objc private func handleGlide(_ g: UIPanGestureRecognizer) {
        guard currentLayout == .letters, !words.isEmpty else { return }
        let pt = g.location(in: keysContainer)

        switch g.state {
        case .began:
            glidePoints = [pt]
            glideLetters = []
            isGlide = false
            if let ch = letterUnder(pt) { glideLetters.append(ch) }

        case .changed:
            glidePoints.append(pt)
            if let ch = letterUnder(pt), glideLetters.last != ch {
                glideLetters.append(ch)
            }
            if !isGlide, polylineLength(glidePoints) > 22, glideLetters.count >= 2 {
                isGlide = true
                hideCallout()
            }
            if isGlide {
                glideEndedAt = Date()
                drawTrail()
            }

        case .ended, .cancelled, .failed:
            if isGlide {
                glideEndedAt = Date()
                if let word = decodeGlide() { insertGlidedWord(word) }
            }
            glideTrail.path = nil
            glidePoints = []
            glideLetters = []
            isGlide = false

        default:
            break
        }
    }

    private func drawTrail() {
        guard glidePoints.count > 1 else { return }
        let path = UIBezierPath()
        path.move(to: glidePoints[0])
        for p in glidePoints.dropFirst() { path.addLine(to: p) }
        glideTrail.path = path.cgPath
    }

    private func letterUnder(_ pt: CGPoint) -> Character? {
        nearestLetter(pt, maxDistance: closestKeyRadius * 1.4)
    }

    private var closestKeyRadius: CGFloat {
        // Half a key width, derived from current letter spacing.
        metrics(rowCount: max(keyRows.count, 1)).unit
    }

    private func neighborLetters(of ch: Character) -> [Character] {
        guard let c = letterCenters[ch] else { return [] }
        let r = closestKeyRadius * 1.4
        return letterCenters.compactMap { (k, center) in
            hypot(center.x - c.x, center.y - c.y) < r ? k : nil
        }
    }

    private func nearestLetter(_ pt: CGPoint, maxDistance: CGFloat) -> Character? {
        var best: (ch: Character, d: CGFloat)?
        for (ch, c) in letterCenters {
            let d = hypot(pt.x - c.x, pt.y - c.y)
            if best == nil || d < best!.d { best = (ch, d) }
        }
        guard let b = best, b.d <= maxDistance else { return nil }
        return b.ch
    }

    /// Shape-matches the swiped path against dictionary words (SHARK²-style): prune by
    /// the start/end keys, then score each candidate by how closely the path traces the
    /// word's ideal key-to-key route, lightly weighted by word frequency.
    private func decodeGlide() -> String? {
        guard glidePoints.count > 2, !letterCenters.isEmpty,
              let startCh = nearestLetter(glidePoints.first!, maxDistance: closestKeyRadius * 1.6),
              let endCh = nearestLetter(glidePoints.last!, maxDistance: closestKeyRadius * 1.6)
        else { return nil }

        var candidates = wordIndexByPair["\(startCh)\(endCh)"] ?? []
        // If few exact start/end matches, relax the END key to its neighbours (a finger
        // often lifts a hair off the intended last key) — but never flood with every word.
        if candidates.count < 3 {
            for n in neighborLetters(of: endCh) {
                candidates += wordIndexByPair["\(startCh)\(n)"] ?? []
            }
        }
        if candidates.isEmpty { candidates = wordIndexByFirst[startCh] ?? [] }
        guard !candidates.isEmpty else { return nil }

        let unit = closestKeyRadius
        let sampled = resample(glidePoints, to: 28)
        var best: (score: CGFloat, idx: Int)?
        for idx in candidates {
            let w = words[idx]
            guard w.count >= 2, let ideal = idealPath(for: w) else { continue }
            let resampledIdeal = resample(ideal, to: 28)
            // Normalize by key size so the score is scale-invariant across devices, then
            // add a light frequency term (lower rank index = more common) as a tie-breaker.
            let shape = shapeDistance(sampled, resampledIdeal) / max(unit, 1)
            let score = shape + CGFloat(log(Double(idx + 2))) * 0.35
            if best == nil || score < best!.score { best = (score, idx) }
        }
        return best.map { words[$0.idx] }
    }

    private func idealPath(for word: String) -> [CGPoint]? {
        var pts: [CGPoint] = []
        for ch in word {
            guard let c = letterCenters[ch] else { return nil }
            pts.append(c)
        }
        return pts.count >= 2 ? pts : nil
    }

    private func insertGlidedWord(_ word: String) {
        // Separate from preceding text with a space (unless we're already at a boundary),
        // and add a trailing space — the standard glide-typing behavior.
        var toInsert = word
        if let last = textDocumentProxy.documentContextBeforeInput?.last, !last.isWhitespace {
            toInsert = " " + toInsert
        }
        toInsert += " "
        textDocumentProxy.insertText(toInsert)
        playClick()
        capture(toInsert)
    }

    // MARK: - Glide math helpers

    private func polylineLength(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<pts.count { total += hypot(pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y) }
        return total
    }

    private func resample(_ pts: [CGPoint], to n: Int) -> [CGPoint] {
        guard pts.count > 1, n > 1 else { return Array(repeating: pts.first ?? .zero, count: n) }
        var cumulative: [CGFloat] = [0]
        for i in 1..<pts.count {
            cumulative.append(cumulative[i-1] + hypot(pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y))
        }
        let total = cumulative.last!
        guard total > 0 else { return Array(repeating: pts[0], count: n) }
        var out: [CGPoint] = []
        for i in 0..<n {
            let target = total * CGFloat(i) / CGFloat(n - 1)
            var j = 1
            while j < pts.count && cumulative[j] < target { j += 1 }
            let j0 = j - 1, j1 = min(j, pts.count - 1)
            let segLen = cumulative[j1] - cumulative[j0]
            let t = segLen > 0 ? (target - cumulative[j0]) / segLen : 0
            out.append(CGPoint(x: pts[j0].x + (pts[j1].x - pts[j0].x) * t,
                               y: pts[j0].y + (pts[j1].y - pts[j0].y) * t))
        }
        return out
    }

    private func shapeDistance(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
        let n = min(a.count, b.count)
        guard n > 0 else { return .greatestFiniteMagnitude }
        var sum: CGFloat = 0
        for i in 0..<n { sum += hypot(a[i].x - b[i].x, a[i].y - b[i].y) }
        return sum / CGFloat(n)
    }

    // MARK: - Key pop-up callout

    private func showCallout(for button: UIButton, text: String) {
        guard currentLayout == .letters else { return }
        calloutView.text = text
        calloutView.textColor = isDarkMode ? .white : .black
        calloutView.backgroundColor = isDarkMode ? UIColor(white: 0.45, alpha: 1) : .white
        let w = button.frame.width * 1.35
        let h = button.frame.height * 1.35
        calloutView.frame = CGRect(x: button.frame.midX - w / 2,
                                   y: button.frame.minY - h - 4,
                                   width: w, height: h)
        calloutView.isHidden = false
    }

    private func hideCallout() { calloutView.isHidden = true }

    // MARK: - Predictive suggestions (iOS-style)

    private var suggestionHasLiteral = false

    private func setupSuggestionBar() {
        suggestionBar.translatesAutoresizingMaskIntoConstraints = true
        suggestionBar.backgroundColor = .clear
        view.addSubview(suggestionBar)

        for i in 0..<3 {
            let b = UIButton(type: .system)
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.6
            b.titleLabel?.lineBreakMode = .byTruncatingTail
            b.setTitleColor(isDarkMode ? .white : .black, for: .normal)
            b.tag = 3000 + i
            b.addTarget(self, action: #selector(suggestionTapped(_:)), for: .touchUpInside)
            suggestionBar.addSubview(b)
            suggestionButtons.append(b)

            if i < 2 {
                let sep = UIView()
                sep.backgroundColor = (isDarkMode ? UIColor.white : UIColor.black).withAlphaComponent(0.16)
                suggestionBar.addSubview(sep)
                suggestionSeparators.append(sep)
            }
        }
        updateSuggestions()
    }

    private func layoutSuggestionBar() {
        let show = currentLayout != .emoji
        suggestionBar.isHidden = !show
        guard show else { return }

        let h = suggestionBarHeight
        suggestionBar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: h)
        let side: CGFloat = isPad ? 8 : 4
        let usable = view.bounds.width - 2 * side
        let slotW = usable / 3
        for (i, b) in suggestionButtons.enumerated() {
            b.frame = CGRect(x: side + CGFloat(i) * slotW, y: 0, width: slotW, height: h)
        }
        for (i, sep) in suggestionSeparators.enumerated() {
            sep.frame = CGRect(x: side + CGFloat(i + 1) * slotW, y: h * 0.25, width: 1, height: h * 0.5)
        }
    }

    /// The run of word characters immediately before the cursor (the word being typed).
    private func currentWord() -> String {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        var chars: [Character] = []
        for ch in before.reversed() {
            if ch.isLetter || ch == "'" { chars.append(ch) } else { break }
        }
        return String(chars.reversed())
    }

    private func updateSuggestions() {
        guard currentLayout != .emoji else { return }
        currentSuggestions = computeSuggestions()
        for (i, b) in suggestionButtons.enumerated() {
            if i < currentSuggestions.count, !currentSuggestions[i].isEmpty {
                let raw = currentSuggestions[i]
                let display = (i == 0 && suggestionHasLiteral) ? "\u{201C}\(raw)\u{201D}" : raw
                b.setTitle(display, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: isPad ? 19 : 17,
                                                 weight: i == 1 ? .semibold : .regular)
                b.isHidden = false
            } else {
                b.setTitle("", for: .normal)
                b.isHidden = true
            }
        }
    }

    /// Builds up to 3 slots: ["literal typed text"] [top prediction] [alternate].
    /// Completions are frequency-ranked from `words.txt`; corrections come from the
    /// system `UITextChecker` (the same engine iOS autocorrect uses).
    private func computeSuggestions() -> [String] {
        let prefix = currentWord()
        guard !prefix.isEmpty else {
            suggestionHasLiteral = false
            return ["I", "The", "I'm"]   // simple sentence starters
        }
        suggestionHasLiteral = true
        let lower = prefix.lowercased()

        var completions: [String] = []
        for w in words where w.hasPrefix(lower) {
            completions.append(applyCase(w, like: prefix))
            if completions.count >= 6 { break }
        }

        var corrections: [String] = []
        let nsr = NSRange(location: 0, length: prefix.utf16.count)
        let misspelled = textChecker.rangeOfMisspelledWord(
            in: prefix, range: nsr, startingAt: 0, wrap: false, language: "en_US")
        if misspelled.location != NSNotFound {
            corrections = (textChecker.guesses(forWordRange: nsr, in: prefix, language: "en_US") ?? [])
                .prefix(4).map { applyCase($0, like: prefix) }
        }

        let prediction = completions.first { $0.lowercased() != lower } ?? corrections.first
        let alternate = completions.first { $0.lowercased() != lower && $0 != prediction }
            ?? corrections.first { $0 != prediction }

        var slots = [prefix]
        if let p = prediction { slots.append(p) }
        if let a = alternate, a != prediction { slots.append(a) }
        return slots
    }

    private func applyCase(_ word: String, like prefix: String) -> String {
        guard let first = prefix.first, first.isUppercase else { return word }
        if prefix.count > 1 && prefix == prefix.uppercased() { return word.uppercased() }
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    @objc private func suggestionTapped(_ sender: UIButton) {
        let idx = sender.tag - 3000
        guard idx >= 0, idx < currentSuggestions.count else { return }
        acceptSuggestion(currentSuggestions[idx])
    }

    private func acceptSuggestion(_ word: String) {
        // Replace the in-progress word with the chosen one (+ trailing space), keeping the
        // capture buffer in sync so suggestion-completed text is collected, not double-counted.
        let partial = currentWord()
        for _ in 0..<partial.count {
            textDocumentProxy.deleteBackward()
            if shouldCapture, !textBuffer.isEmpty { textBuffer.removeLast() }
        }
        let out = word + " "
        textDocumentProxy.insertText(out)
        playClick()
        capture(out)              // data collection: counts toward contributed tokens
        updateSuggestions()
    }

    // MARK: - Collection indicator

    private func updateCollectionIndicator() {
        if shouldCapture {
            collectionIndicator.alpha = 1
            startPulse()
        } else {
            collectionIndicator.alpha = 0
            collectionIndicator.layer.removeAllAnimations()
        }
    }

    private func startPulse() {
        collectionIndicator.layer.removeAllAnimations()
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0; pulse.toValue = 0.35
        pulse.duration = 1.1; pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        collectionIndicator.layer.add(pulse, forKey: "pulse")
    }
}

// MARK: - Glide gesture delegate

extension KeyboardViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - Emoji collection view

private final class EmojiCell: UICollectionViewCell {
    static let reuseID = "EmojiCell"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.frame = contentView.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ emoji: String, fontSize: CGFloat) {
        label.font = .systemFont(ofSize: fontSize)
        label.text = emoji
    }
}

extension KeyboardViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        emojiModel.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard section < emojiModel.count else { return 0 }
        return emojiModel[section].emojis.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseID, for: indexPath) as! EmojiCell
        cell.configure(emoji(at: indexPath), fontSize: isPad ? 32 : 29)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        // Square cells sized so exactly `emojiRows` fit vertically; the grid then flows
        // top-to-bottom and scrolls horizontally (column-major), like the iOS keyboard.
        let side = floor(collectionView.bounds.height / CGFloat(emojiRows))
        return CGSize(width: side, height: side)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let e = emoji(at: indexPath)
        textDocumentProxy.insertText(e)
        playClick()
        capture(e)
        recordRecentEmoji(e)
        collectionView.deselectItem(at: indexPath, animated: false)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard currentLayout == .emoji, scrollView === emojiCollection else { return }
        let probe = CGPoint(x: scrollView.contentOffset.x + 10, y: scrollView.bounds.height / 2)
        if let ip = emojiCollection.indexPathForItem(at: probe) {
            highlightEmojiTab(section: ip.section)
        }
    }

    private func emoji(at indexPath: IndexPath) -> String {
        guard indexPath.section < emojiModel.count,
              indexPath.item < emojiModel[indexPath.section].emojis.count else { return "" }
        return emojiModel[indexPath.section].emojis[indexPath.item]
    }
}

// MARK: - Helpers

private extension Array where Element == CGFloat {
    /// Replaces the single `-1` placeholder (the space bar) with whatever width is
    /// left over after the fixed keys and gaps, so the row fills the keyboard exactly.
    func fillingSpace(rowWidth: CGFloat, gap: CGFloat) -> [CGFloat] {
        let fixed = filter { $0 >= 0 }.reduce(0, +)
        let gaps = CGFloat(count - 1) * gap
        let space = Swift.max(rowWidth * 0.18, rowWidth - fixed - gaps)
        return map { $0 < 0 ? space : $0 }
    }
}
