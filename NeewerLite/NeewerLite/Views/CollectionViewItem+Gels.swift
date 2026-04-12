//
//  CollectionViewItem+Gels.swift
//  NeewerLite
//
//  Created by Xu Lian on 4/10/26.
//

import Cocoa

// MARK: - Gel State

/// Tracks the transient gel state for one device card.
/// None of these values are persisted across launches.
final class GelState {
    /// The gel currently applied, or `nil` if none.
    var activeGel: NeewerGel?
    /// Optional second gel slot — used when the user stacks two gels.
    var stackedGel: NeewerGel?
    /// Application mode: false = Full Colour, true = Tint over CCT
    var tintMode: Bool = false
    /// The device's `lightMode` before the gel was applied, so "Clear Gel" can restore it.
    var priorLightMode: NeewerLight.Mode = .CCTMode
    /// The brightness level before applying the gel (0–100), for restoring on clear.
    var priorBrightness: Double = 50
    /// The CCT before applying the gel, for restoring on clear.
    var priorCCT: Double = 53
    /// The user's *intended* brightness (0–100), set exclusively from slider interactions.
    /// Never overwritten by device-feedback so effectiveBrightness scaling doesn't cascade.
    var intentBrightness: Double = 50

    // View references (populated by buildGelsView; weak to avoid retain cycles)
    weak var resultSwatch: NSView?
    weak var resultLabel: NSTextField?
    weak var gelCollectionView: NSCollectionView?
    weak var intensityValueLabel: NSTextField?
    /// The gel-tab intensity slider — stored here so we never need to find it by tag,
    /// and so we can give it a tag that processSubView won't recognise.
    weak var intensitySlider: NLSlider?

    /// Resolved stacked output (nil if no active gel).
    var stackedResult: StackedGel? {
        guard let g1 = activeGel else { return nil }
        if let g2 = stackedGel {
            return g1.stacked(with: g2)
        }
        // Single gel — wrap it in a StackedGel for uniform handling.
        return StackedGel(
            hue: g1.hue,
            saturation: g1.saturation,
            transmissionPercent: g1.transmissionPercent,
            mireds: g1.mireds,
            sourceGels: [g1]
        )
    }
}

// MARK: - CollectionViewItem Gel extension

extension CollectionViewItem: NSCollectionViewDelegate, NSCollectionViewDataSource {

    // Gel state is stored per-device (keyed by identifier) so it survives
    // cell recycling when the collection view reloads.
    private static var gelStateStore: [String: GelState] = [:]

    var gelState: GelState {
        let key = device?.identifier ?? ""
        if let existing = CollectionViewItem.gelStateStore[key] {
            return existing
        }
        let state = GelState()
        CollectionViewItem.gelStateStore[key] = state
        return state
    }

    // MARK: - Build Gels Tab View

    func buildGelsView(device dev: NeewerLight) -> NSView {
        let viewWidth = self.lightModeTabView.bounds.width
        let viewHeight = self.lightModeTabView.bounds.height - 46
        let container = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: viewHeight))
        container.autoresizingMask = [.width, .height]

        let padX: CGFloat = 10
        let padY: CGFloat = 8

        // ── Bottom strip: result info + Clear Gel ──────────────────────────
        let bottomStripHeight: CGFloat = 30
        let bottomY: CGFloat = padY

        let resultSwatch = NSView(frame: NSRect(x: padX, y: bottomY + 4, width: 22, height: 22))
        resultSwatch.wantsLayer = true
        resultSwatch.layer?.cornerRadius = 4
        resultSwatch.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.2).cgColor
        gelState.resultSwatch = resultSwatch
        container.addSubview(resultSwatch)

        let resultLabel = NSTextField(labelWithString: "No gel applied")
        resultLabel.frame = NSRect(x: padX + 28, y: bottomY + 6, width: viewWidth - padX * 2 - 110, height: 18)
        resultLabel.font = NSFont.systemFont(ofSize: 10)
        resultLabel.textColor = NSColor.secondaryLabelColor
        resultLabel.autoresizingMask = [.width]
        gelState.resultLabel = resultLabel
        container.addSubview(resultLabel)

        let clearButton = NSButton(title: "Clear Gel", target: self, action: #selector(clearGelTapped(_:)))
        clearButton.bezelStyle = .rounded
        clearButton.font = NSFont.systemFont(ofSize: 10)
        clearButton.frame = NSRect(x: viewWidth - padX - 90, y: bottomY + 2, width: 90, height: 24)
        clearButton.autoresizingMask = [.minXMargin]
        container.addSubview(clearButton)

        // ── Intensity slider ───────────────────────────────────────────────
        let sliderAreaY = bottomStripHeight + padY * 2
        let sliderLabelW: CGFloat = 55

        let intensityLabel = NSTextField(labelWithString: "Intensity")
        intensityLabel.font = NSFont.systemFont(ofSize: 11)
        intensityLabel.alignment = .right
        intensityLabel.frame = NSRect(x: padX, y: sliderAreaY, width: sliderLabelW, height: 20)
        container.addSubview(intensityLabel)

        let intensitySlider = NLSlider(frame: NSRect(x: padX + sliderLabelW + 4,
                                                     y: sliderAreaY,
                                                     width: viewWidth - padX * 2 - sliderLabelW - 60,
                                                     height: 20))
        intensitySlider.autoresizingMask = [.width]
        // Use a private tag (not ControlTag.brr) so processSubView never overwrites
        // this slider with device-reported brightness.
        intensitySlider.tag = ControlTag.gelMode.rawValue + 100
        intensitySlider.type = .brr
        intensitySlider.stepSize = 1.0
        intensitySlider.minValue = 0.0
        intensitySlider.maxValue = 100.0
        intensitySlider.currentValue = CGFloat(dev.brrValue.value)
        intensitySlider.customBarDrawing = NLSlider.brightnessBar()
        if gelState.activeGel == nil {
            gelState.intentBrightness = Double(dev.brrValue.value)
        }
        gelState.intensitySlider = intensitySlider
        intensitySlider.callback = { [weak self] val in
            guard let self = self else { return }
            self.applyGelIfActive(brightness: val)
        }
        container.addSubview(intensitySlider)

        let intensityValueLabel = NSTextField(labelWithString: "\(dev.brrValue.value)%")
        intensityValueLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        intensityValueLabel.alignment = .left
        intensityValueLabel.frame = NSRect(x: intensitySlider.frame.maxX + 4, y: sliderAreaY,
                                           width: 40, height: 20)
        intensityValueLabel.autoresizingMask = [.minXMargin]
        gelState.intensityValueLabel = intensityValueLabel
        container.addSubview(intensityValueLabel)

        // ── Tint Mode radio buttons ────────────────────────────────────────
        let radioY = sliderAreaY + 28

        let radioLabel = NSTextField(labelWithString: "Mode")
        radioLabel.font = NSFont.systemFont(ofSize: 11)
        radioLabel.alignment = .right
        radioLabel.frame = NSRect(x: padX, y: radioY, width: sliderLabelW, height: 18)
        container.addSubview(radioLabel)

        let radioFull = NSButton(radioButtonWithTitle: "Full Colour", target: self,
                                 action: #selector(gelModeChanged(_:)))
        radioFull.controlSize = .small
        radioFull.font = NSFont.systemFont(ofSize: 11)
        radioFull.frame = NSRect(x: padX + sliderLabelW + 8, y: radioY, width: 100, height: 18)
        radioFull.tag = ControlTag.gelMode.rawValue
        radioFull.state = .on
        container.addSubview(radioFull)

        let radioTint = NSButton(radioButtonWithTitle: "Tint over CCT", target: self,
                                 action: #selector(gelModeChanged(_:)))
        radioTint.controlSize = .small
        radioTint.font = NSFont.systemFont(ofSize: 11)
        radioTint.frame = NSRect(x: padX + sliderLabelW + 118, y: radioY, width: 120, height: 18)
        radioTint.tag = ControlTag.gelMode.rawValue + 1
        radioTint.state = .off
        container.addSubview(radioTint)

        // ── Swatch grid ────────────────────────────────────────────────────
        let gridY = radioY + 38
        let gridHeight = viewHeight - gridY - padY

        let scrollView = NSScrollView(frame: NSRect(x: padX, y: gridY,
                                                    width: viewWidth - padX * 2, height: gridHeight))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.itemSize = NSSize(width: 68, height: 68)
        flowLayout.minimumInteritemSpacing = 6
        flowLayout.minimumLineSpacing = 6
        flowLayout.sectionInset = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = flowLayout
        collectionView.register(GelSwatchCell.self,
                                forItemWithIdentifier: GelSwatchCell.identifier)
        collectionView.isSelectable = true
        collectionView.allowsEmptySelection = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.delegate = self
        collectionView.dataSource = self
        gelState.gelCollectionView = collectionView

        scrollView.documentView = collectionView
        container.addSubview(scrollView)

        // Restore previous gel selection after tab rebuild
        let state = gelState
        if let activeGel = state.activeGel {
            let gels = GelLibrary.shared.all
            if let idx = gels.firstIndex(of: activeGel) {
                let indexPath = IndexPath(item: idx, section: 0)
                collectionView.reloadData()
                collectionView.selectItems(at: [indexPath], scrollPosition: .centeredVertically)
            }
            // Restore intensity slider to user's intended brightness
            intensitySlider.currentValue = CGFloat(state.intentBrightness)
            intensityValueLabel.stringValue = "\(Int(state.intentBrightness))%"
            // Restore tint mode radio buttons
            if state.tintMode {
                radioFull.state = .off
                radioTint.state = .on
            }
            // Update result display with restored state
            updateGelResultDisplay()
        }

        return container
    }

    // MARK: - NSCollectionViewDataSource

    public func collectionView(_ collectionView: NSCollectionView,
                               numberOfItemsInSection section: Int) -> Int {
        guard collectionView === gelState.gelCollectionView else { return 0 }
        return GelLibrary.shared.all.count
    }

    public func collectionView(_ collectionView: NSCollectionView,
                               itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: GelSwatchCell.identifier, for: indexPath)
        guard let cell = item as? GelSwatchCell else { return item }
        let gels = GelLibrary.shared.all
        if indexPath.item < gels.count {
            cell.gel = gels[indexPath.item]
        }
        return cell
    }

    // MARK: - NSCollectionViewDelegate

    public func collectionView(_ collectionView: NSCollectionView,
                               didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard collectionView === gelState.gelCollectionView else { return }
        guard let indexPath = indexPaths.first else { return }
        let gels = GelLibrary.shared.all
        guard indexPath.item < gels.count else { return }
        let selectedGel = gels[indexPath.item]
        gelState.activeGel = selectedGel
        applyActiveGel()
        updateGelResultDisplay()
    }

    // MARK: - Actions

    @objc func clearGelTapped(_ sender: NSButton) {
        clearActiveGel()
    }

    @objc func gelModeChanged(_ sender: NSButton) {
        // Both radio buttons share the same action; determine which one is now on.
        guard let gelTabView = gelTabViewContainer() else { return }
        let fullBtn = gelTabView.subviews.first(where: { $0.tag == ControlTag.gelMode.rawValue }) as? NSButton
        gelState.tintMode = (fullBtn?.state != .on)
        applyActiveGel()
    }

    // MARK: - Apply / Clear Logic

    /// Applies the currently active gel (and optional stacked gel) to the physical light.
    /// Pass an explicit `brightness` to avoid reading back from the slider (prevents callback loops).
    func applyActiveGel(brightness overrideBrr: Double? = nil) {
        guard let dev = device, dev.supportRGB else { return }
        guard let result = gelState.stackedResult else { return }

        // Always use intentBrightness as the base so device-feedback never cascades.
        let brr = overrideBrr ?? gelState.intentBrightness

        if gelState.tintMode {
            // Tint over CCT: blend gel saturation at intensity fraction
            // S_applied = S_gel × (brr / 100)
            let tintFraction = brr / 100.0
            let appliedSat = (result.saturation * tintFraction) / 100.0  // unit float
            dev.lightMode = .HSIMode
            dev.setHSILightValues(brr100: CGFloat(brr),
                                  hue: CGFloat(result.hue) / 360.0,
                                  hue360: CGFloat(result.hue),
                                  sat: CGFloat(appliedSat))
        } else {
            // Full Colour: replace output entirely with gel colour.
            // Scale brightness by physical transmission factor.
            let scaledBrr = result.effectiveBrightness(base: brr)
            dev.lightMode = .HSIMode
            dev.setHSILightValues(brr100: CGFloat(scaledBrr),
                                  hue: CGFloat(result.hue) / 360.0,
                                  hue360: CGFloat(result.hue),
                                  sat: CGFloat(result.saturation) / 100.0)
        }
        updateGelResultDisplay()
    }

    /// Applies the gel with an explicit brightness (called from intensity slider callback).
    func applyGelIfActive(brightness: Double) {
        guard gelState.activeGel != nil else { return }
        gelState.intentBrightness = brightness  // record user intent before applying
        gelState.intensityValueLabel?.stringValue = "\(Int(brightness))%"
        applyActiveGel(brightness: brightness)
    }

    /// Restores the device to its pre-gel state.
    func clearActiveGel() {
        guard let dev = device else { return }
        let state = gelState
        state.activeGel = nil
        state.stackedGel = nil

        // Restore device to prior mode
        if state.priorLightMode == .CCTMode {
            dev.setCCTLightValues(brr: CGFloat(state.priorBrightness),
                                  cct: CGFloat(state.priorCCT),
                                  gmm: CGFloat(dev.gmmValue.value))
        } else {
            dev.setHSILightValues(brr100: CGFloat(state.priorBrightness),
                                  hue: CGFloat(dev.hueValue.value) / 360.0,
                                  hue360: CGFloat(dev.hueValue.value),
                                  sat: CGFloat(dev.satValue.value) / 100.0)
        }

        // Clear selection in swatch grid
        reloadGelSwatchGrid()
        updateGelResultDisplay()
    }

    // MARK: - Helpers

    private func currentGelIntensity() -> Double {
        if let slider = gelBrrSlider() {
            return Double(slider.currentValue)
        }
        return Double(device?.brrValue.value ?? 50)
    }

    private func gelTabViewContainer() -> NSView? {
        let idx = lightModeTabView.indexOfTabViewItem(withIdentifier: TabId.gel.rawValue)
        guard idx != NSNotFound else { return nil }
        return lightModeTabView.tabViewItem(at: idx).view
    }

    private func gelBrrSlider() -> NLSlider? {
        return gelState.intensitySlider
    }

    private func reloadGelSwatchGrid() {
        gelState.gelCollectionView?.reloadData()
    }

    private func updateGelResultDisplay() {
        guard let swatch = gelState.resultSwatch,
              let label = gelState.resultLabel else { return }

        if let result = gelState.stackedResult {
            swatch.layer?.backgroundColor = result.swatchColor.cgColor
            var info = result.sourceGels.map { $0.name }.joined(separator: " + ")
            info += "  H:\(Int(result.hue))°  S:\(Int(result.saturation))%"
            if result.transmissionPercent < 99 {
                info += "  T:\(Int(result.transmissionPercent))%"
            }
            label.stringValue = info
            label.textColor = NSColor.labelColor
        } else {
            swatch.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.2).cgColor
            label.stringValue = "No gel applied"
            label.textColor = NSColor.secondaryLabelColor
        }
    }
}
