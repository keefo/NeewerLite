//
//  CenteredFlowLayout.swift
//  NeewerLite
//
//  Created by Xu Lian on 4/18/26.
//

import Cocoa

/// A centered flow layout for `NSCollectionView`.
///
/// Lays out fixed-size items in rows, centered horizontally within the
/// available width — similar to CSS flexbox with `justify-content: center`.
/// As the window widens, more columns appear; as it narrows, columns drop.
/// The last row (which may have fewer items) is also centered.
///
/// ## Why a custom layout instead of `NSCollectionViewFlowLayout`?
///
/// `NSCollectionViewFlowLayout` justifies items by stretching inter-item
/// spacing to fill each row edge-to-edge. There is no setting to disable
/// this behavior — it is baked into the layout engine. Overriding
/// `layoutAttributesForElements(in:)` to re-center items causes a
/// feedback loop because the superclass caches attributes mutably.
/// A fully custom `NSCollectionViewLayout` avoids all of these issues.
///
/// ## Width source: clip view, not collection view
///
/// The collection view's own `bounds.width` can shrink when a legacy
/// (non-overlay) scrollbar appears, which reduces the column count and
/// makes the content shorter, which hides the scrollbar, which widens
/// the bounds, which increases columns — an infinite layout loop.
/// Reading the scroll view's **clip view** (`contentView.bounds.width`)
/// gives the stable visible width regardless of scrollbar state.
///
/// `collectionViewContentSize.width` still returns the *collection view's*
/// `bounds.width` so AppKit does not see a wider content area and does
/// not introduce a horizontal scrollbar.
///
/// ## Invalidation
///
/// Layout is invalidated only when the visible width changes by more than
/// 0.5 pt, preventing sub-pixel thrashing during live resize.
class CenteredFlowLayout: NSCollectionViewLayout {

    var itemSize: NSSize = NSSize(width: 540, height: 300)
    var interitemSpacing: CGFloat = 10
    var lineSpacing: CGFloat = 10
    var edgeInsets: NSEdgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

    private var cachedAttributes: [NSCollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0
    private var lastBoundsWidth: CGFloat = 0

    // Return the collection view's own width (not the scroll view's) to
    // avoid making the content area wider than the view and triggering a
    // horizontal scrollbar.
    override var collectionViewContentSize: NSSize {
        let w = collectionView?.bounds.width ?? 0
        return NSSize(width: w, height: contentHeight)
    }

    override func prepare() {
        super.prepare()
        cachedAttributes.removeAll()

        guard let collectionView = collectionView else { return }

        // Use the clip view's width — stable even when a scrollbar appears.
        let visibleWidth: CGFloat
        if let scrollView = collectionView.enclosingScrollView {
            visibleWidth = scrollView.contentView.bounds.width
        } else {
            visibleWidth = collectionView.bounds.width
        }

        let sectionCount = collectionView.numberOfSections
        guard sectionCount > 0 else {
            contentHeight = 0
            return
        }

        let itemCount = collectionView.numberOfItems(inSection: 0)
        guard itemCount > 0 else {
            contentHeight = 0
            return
        }

        lastBoundsWidth = visibleWidth

        // Column count: how many items fit side-by-side after subtracting
        // left/right edge insets? The formula accounts for N items needing
        // only (N-1) gaps:
        //   usableWidth >= N * itemWidth + (N-1) * spacing
        //   usableWidth + spacing >= N * (itemWidth + spacing)
        //   N = floor((usableWidth + spacing) / (itemWidth + spacing))
        let usableWidth = visibleWidth - edgeInsets.left - edgeInsets.right
        let columns = max(1, Int(floor((usableWidth + interitemSpacing) / (itemSize.width + interitemSpacing))))

        // Walk through items row by row, centering each row.
        var y = edgeInsets.top
        var index = 0

        while index < itemCount {
            // The last row may have fewer items than `columns`.
            let rowCount = min(columns, itemCount - index)
            let rowWidth = CGFloat(rowCount) * itemSize.width + CGFloat(rowCount - 1) * interitemSpacing
            // Center the row within the full visible width.
            let rowX = (visibleWidth - rowWidth) / 2

            for col in 0..<rowCount {
                let indexPath = IndexPath(item: index, section: 0)
                let attr = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
                attr.frame = NSRect(
                    x: rowX + CGFloat(col) * (itemSize.width + interitemSpacing),
                    y: y,
                    width: itemSize.width,
                    height: itemSize.height
                )
                cachedAttributes.append(attr)
                index += 1
            }

            y += itemSize.height + lineSpacing
        }

        contentHeight = y - lineSpacing + edgeInsets.bottom
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        return cachedAttributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item < cachedAttributes.count else { return nil }
        return cachedAttributes[indexPath.item]
    }

    // Invalidate only when width changes materially (> 0.5 pt).
    // This avoids re-layout from sub-pixel rounding during live resize.
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        let currentWidth: CGFloat
        if let scrollView = collectionView?.enclosingScrollView {
            currentWidth = scrollView.contentView.bounds.width
        } else {
            currentWidth = lastBoundsWidth
        }
        return abs(newBounds.width - currentWidth) > 0.5 || abs(newBounds.width - lastBoundsWidth) > 0.5
    }
}
