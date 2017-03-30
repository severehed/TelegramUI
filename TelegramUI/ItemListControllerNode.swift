import Foundation
import Display
import SwiftSignalKit
import TelegramCore

typealias ItemListSectionId = Int32

protocol ItemListNodeEntry: Equatable, Comparable, Identifiable {
    associatedtype ItemGenerationArguments
    
    var section: ItemListSectionId { get }
    
    func item(_ arguments: ItemGenerationArguments) -> ListViewItem
}

private struct ItemListNodeEntryTransition {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
}

private func preparedItemListNodeEntryTransition<Entry: ItemListNodeEntry>(from fromEntries: [Entry], to toEntries: [Entry], arguments: Entry.ItemGenerationArguments) -> ItemListNodeEntryTransition {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries)
    
    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(arguments), directionHint: nil) }
    let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(arguments), directionHint: nil) }
    
    return ItemListNodeEntryTransition(deletions: deletions, insertions: insertions, updates: updates)
}

enum ItemListStyle {
    case plain
    case blocks
}

private struct ItemListNodeTransition<Entry: ItemListNodeEntry> {
    let entries: ItemListNodeEntryTransition
    let updateStyle: ItemListStyle?
    let emptyStateItem: ItemListControllerEmptyStateItem?
    let focusItemTag: ItemListItemTag?
    let firstTime: Bool
    let animated: Bool
    let animateAlpha: Bool
    let mergedEntries: [Entry]
}

struct ItemListNodeState<Entry: ItemListNodeEntry> {
    let entries: [Entry]
    let style: ItemListStyle
    let emptyStateItem: ItemListControllerEmptyStateItem?
    let animateChanges: Bool
    let focusItemTag: ItemListItemTag?
    
    init(entries: [Entry], style: ItemListStyle, focusItemTag: ItemListItemTag? = nil, emptyStateItem: ItemListControllerEmptyStateItem? = nil, animateChanges: Bool = true) {
        self.entries = entries
        self.style = style
        self.emptyStateItem = emptyStateItem
        self.animateChanges = animateChanges
        self.focusItemTag = focusItemTag
    }
}

private final class ItemListNodeOpaqueState<Entry: ItemListNodeEntry> {
    let mergedEntries: [Entry]
    
    init(mergedEntries: [Entry]) {
        self.mergedEntries = mergedEntries
    }
}

final class ItemListNodeVisibleEntries<Entry: ItemListNodeEntry>: Sequence {
    let iterate: () -> Entry?
    
    init(iterate: @escaping () -> Entry?) {
        self.iterate = iterate
    }
    
    func makeIterator() -> AnyIterator<Entry> {
        return AnyIterator { () -> Entry? in
            return self.iterate()
        }
    }
}

final class ItemListNode<Entry: ItemListNodeEntry>: ASDisplayNode {
    private var _ready = ValuePromise<Bool>()
    public var ready: Signal<Bool, NoError> {
        return self._ready.get()
    }
    private var didSetReady = false
    
    let listNode: ListView
    private var emptyStateItem: ItemListControllerEmptyStateItem?
    private var emptyStateNode: ItemListControllerEmptyStateItemNode?
    
    private let transitionDisposable = MetaDisposable()
    
    private var enqueuedTransitions: [ItemListNodeTransition<Entry>] = []
    private var validLayout: (ContainerViewLayout, CGFloat)?
    
    var dismiss: (() -> Void)?
    
    var visibleEntriesUpdated: ((ItemListNodeVisibleEntries<Entry>) -> Void)?
    
    init(state: Signal<(ItemListNodeState<Entry>, Entry.ItemGenerationArguments), NoError>) {
        self.listNode = ListView()
        
        super.init(viewBlock: {
            return UITracingLayerView()
        }, didLoad: nil)
        
        self.addSubnode(self.listNode)
        
        self.backgroundColor = UIColor(0xefeff4)
        
        self.listNode.displayedItemRangeChanged = { [weak self] displayedRange, opaqueTransactionState in
            if let strongSelf = self, let visibleEntriesUpdated = strongSelf.visibleEntriesUpdated, let mergedEntries = (opaqueTransactionState as? ItemListNodeOpaqueState<Entry>)?.mergedEntries {
                if let visible = displayedRange.visibleRange {
                    let indexRange = (visible.firstIndex, visible.lastIndex)
                    
                    var index = indexRange.0
                    let iterator = ItemListNodeVisibleEntries<Entry>(iterate: {
                        var item: Entry?
                        if index <= indexRange.1 {
                            item = mergedEntries[index]
                        }
                        index += 1
                        return item
                    })
                    visibleEntriesUpdated(iterator)
                }
            }
        }
        
        let previousState = Atomic<ItemListNodeState<Entry>?>(value: nil)
        self.transitionDisposable.set(((state |> map { state, arguments -> ItemListNodeTransition<Entry> in
            assert(state.entries == state.entries.sorted())
            let previous = previousState.swap(state)
            let transition = preparedItemListNodeEntryTransition(from: previous?.entries ?? [], to: state.entries, arguments: arguments)
            var updatedStyle: ItemListStyle?
            if previous?.style != state.style {
                updatedStyle = state.style
            }
            return ItemListNodeTransition(entries: transition, updateStyle: updatedStyle, emptyStateItem: state.emptyStateItem, focusItemTag: state.focusItemTag, firstTime: previous == nil, animated: previous != nil && state.animateChanges, animateAlpha: previous != nil && !state.animateChanges, mergedEntries: state.entries)
        }) |> deliverOnMainQueue).start(next: { [weak self] transition in
            if let strongSelf = self {
                strongSelf.enqueueTransition(transition)
            }
        }))
    }
    
    deinit {
        self.transitionDisposable.dispose()
    }
    
    func animateIn() {
        self.layer.animatePosition(from: CGPoint(x: self.layer.position.x, y: self.layer.position.y + self.layer.bounds.size.height), to: self.layer.position, duration: 0.5, timingFunction: kCAMediaTimingFunctionSpring)
    }
    
    func animateOut() {
        self.layer.animatePosition(from: self.layer.position, to: CGPoint(x: self.layer.position.x, y: self.layer.position.y + self.layer.bounds.size.height), duration: 0.2, timingFunction: kCAMediaTimingFunctionEaseInEaseOut, removeOnCompletion: false, completion: { [weak self] _ in
            if let strongSelf = self {
                strongSelf.dismiss?()
            }
        })
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        var duration: Double = 0.0
        var curve: UInt = 0
        switch transition {
            case .immediate:
                break
            case let .animated(animationDuration, animationCurve):
                duration = animationDuration
                switch animationCurve {
                    case .easeInOut:
                        break
                    case .spring:
                        curve = 7
                }
        }
        
        let listViewCurve: ListViewAnimationCurve
        if curve == 7 {
            listViewCurve = .Spring(duration: duration)
        } else {
            listViewCurve = .Default
        }
        
        var insets = layout.insets(options: [.input])
        insets.top += navigationBarHeight
        
        self.listNode.bounds = CGRect(x: 0.0, y: 0.0, width: layout.size.width, height: layout.size.height)
        self.listNode.position = CGPoint(x: layout.size.width / 2.0, y: layout.size.height / 2.0)
        
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: nil, updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: layout.size, insets: insets, duration: duration, curve: listViewCurve), stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        if let emptyStateNode = self.emptyStateNode {
            emptyStateNode.updateLayout(layout: layout, navigationBarHeight: navigationBarHeight, transition: transition)
        }
        
        let dequeue = self.validLayout == nil
        self.validLayout = (layout, navigationBarHeight)
        if dequeue {
            self.dequeueTransitions()
        }
    }
    
    private func enqueueTransition(_ transition: ItemListNodeTransition<Entry>) {
        self.enqueuedTransitions.append(transition)
        if self.validLayout != nil {
            self.dequeueTransitions()
        }
    }
    
    private func dequeueTransitions() {
        while !self.enqueuedTransitions.isEmpty {
            let transition = self.enqueuedTransitions.removeFirst()
            
            if let updateStyle = transition.updateStyle {
                switch updateStyle {
                case .plain:
                    self.backgroundColor = .white
                case .blocks:
                    self.backgroundColor = UIColor(0xefeff4)
                }
            }
            var options = ListViewDeleteAndInsertOptions()
            if transition.firstTime {
                options.insert(.Synchronous)
                options.insert(.LowLatency)
            } else if transition.animated {
                options.insert(.AnimateInsertion)
            } else if transition.animateAlpha {
                options.insert(.PreferSynchronousResourceLoading)
                options.insert(.PreferSynchronousDrawing)
                options.insert(.AnimateAlpha)
            }
            let focusItemTag = transition.focusItemTag
            self.listNode.transaction(deleteIndices: transition.entries.deletions, insertIndicesAndItems: transition.entries.insertions, updateIndicesAndItems: transition.entries.updates, options: options, updateOpaqueState: ItemListNodeOpaqueState(mergedEntries: transition.mergedEntries), completion: { [weak self] _ in
                if let strongSelf = self {
                    if !strongSelf.didSetReady {
                        strongSelf.didSetReady = true
                        strongSelf._ready.set(true)
                    }
                    
                    if let focusItemTag = focusItemTag {
                        strongSelf.listNode.forEachItemNode { itemNode in
                            if let itemNode = itemNode as? ItemListItemNode, let itemTag = itemNode.tag, itemTag.isEqual(to: focusItemTag) {
                                if let focusableNode = itemNode as? ItemListItemFocusableNode {
                                    focusableNode.focus()
                                }
                            }
                        }
                    }
                }
            })
            var updateEmptyStateItem = false
            if let emptyStateItem = self.emptyStateItem, let updatedEmptyStateItem = transition.emptyStateItem {
                updateEmptyStateItem = !emptyStateItem.isEqual(to: updatedEmptyStateItem)
            } else if (self.emptyStateItem != nil) != (transition.emptyStateItem != nil) {
                updateEmptyStateItem = true
            }
            if updateEmptyStateItem {
                self.emptyStateItem = transition.emptyStateItem
                if let emptyStateItem = transition.emptyStateItem {
                    let updatedNode = emptyStateItem.node(current: self.emptyStateNode)
                    if let emptyStateNode = self.emptyStateNode, updatedNode !== emptyStateNode {
                        emptyStateNode.removeFromSupernode()
                    }
                    if self.emptyStateNode !== updatedNode {
                        self.emptyStateNode = updatedNode
                        if let validLayout = self.validLayout {
                            updatedNode.updateLayout(layout: validLayout.0, navigationBarHeight: validLayout.1, transition: .immediate)
                        }
                        self.addSubnode(updatedNode)
                    }
                } else if let emptyStateNode = self.emptyStateNode {
                    emptyStateNode.removeFromSupernode()
                    self.emptyStateNode = nil
                }
            }
        }
    }
    
    func scrollToTop() {
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: ListViewScrollToItem(index: 0, position: .Top, animated: true, curve: .Default, directionHint: .Up), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
    }
}