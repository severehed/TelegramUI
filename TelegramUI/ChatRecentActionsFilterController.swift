import Foundation
import Display
import SwiftSignalKit
import Postbox
import TelegramCore

private final class ChatRecentActionsFilterControllerArguments {
    let account: Account
    
    let toggleAllActions: () -> Void
    let toggleAction: ([AdminLogEventsFlags]) -> Void
    let toggleAllAdmins: () -> Void
    let toggleAdmin: (PeerId) -> Void
    
    init(account: Account, toggleAllActions: @escaping () -> Void, toggleAction: @escaping ([AdminLogEventsFlags]) -> Void, toggleAllAdmins: @escaping () -> Void, toggleAdmin: @escaping (PeerId) -> Void) {
        self.account = account
        self.toggleAllActions = toggleAllActions
        self.toggleAction = toggleAction
        self.toggleAllAdmins = toggleAllAdmins
        self.toggleAdmin = toggleAdmin
    }
}

private enum ChatRecentActionsFilterSection: Int32 {
    case actions
    case admins
}

private enum ChatRecentActionsFilterEntryStableId: Hashable {
    case index(Int32)
    case peer(PeerId)
    
    var hashValue: Int {
        switch self {
            case let .index(index):
                return index.hashValue
            case let .peer(peerId):
                return peerId.hashValue
        }
    }
    
    static func ==(lhs: ChatRecentActionsFilterEntryStableId, rhs: ChatRecentActionsFilterEntryStableId) -> Bool {
        switch lhs {
            case let .index(index):
                if case .index(index) = rhs {
                    return true
                } else {
                    return false
                }
            case let .peer(peerId):
                if case .peer(peerId) = rhs {
                    return true
                } else {
                    return false
                }
        }
    }
}

private enum ChatRecentActionsFilterEntry: ItemListNodeEntry {
    case actionsTitle(PresentationTheme, String)
    case allActions(PresentationTheme, String, Bool)
    case actionItem(PresentationTheme, Int32, [AdminLogEventsFlags], String, Bool)
    
    case adminsTitle(PresentationTheme, String)
    case allAdmins(PresentationTheme, String, Bool)
    case adminPeerItem(PresentationTheme, PresentationStrings, Int32, RenderedChannelParticipant, Bool)
    
    var section: ItemListSectionId {
        switch self {
            case .actionsTitle, .allActions, .actionItem:
                return ChatRecentActionsFilterSection.actions.rawValue
            case .adminsTitle, .allAdmins, .adminPeerItem:
                return ChatRecentActionsFilterSection.admins.rawValue
        }
    }
    
    var stableId: ChatRecentActionsFilterEntryStableId {
        switch self {
            case .actionsTitle:
                return .index(0)
            case .allActions:
                return .index(1)
            case let .actionItem(_, index, _, _, _):
                return .index(100 + index)
            case .adminsTitle:
                return .index(200)
            case .allAdmins:
                return .index(201)
            case let .adminPeerItem(_, _, _, participant, _):
                return .peer(participant.peer.id)
        }
    }
    
    static func ==(lhs: ChatRecentActionsFilterEntry, rhs: ChatRecentActionsFilterEntry) -> Bool {
        switch lhs {
            case let .actionsTitle(lhsTheme, lhsText):
                if case let .actionsTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .allActions(lhsTheme, lhsText, lhsValue):
                if case let .allActions(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .actionItem(lhsTheme, lhsIndex, lhsFlags, lhsText, lhsValue):
                if case let .actionItem(rhsTheme, rhsIndex, rhsFlags, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsIndex == rhsIndex, lhsFlags == rhsFlags, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .adminsTitle(lhsTheme, lhsText):
                if case let .adminsTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .allAdmins(lhsTheme, lhsText, lhsValue):
                if case let .allAdmins(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .adminPeerItem(lhsTheme, lhsStrings, lhsIndex, lhsParticipant, lhsChecked):
                if case let .adminPeerItem(rhsTheme, rhsStrings, rhsIndex, rhsParticipant, rhsChecked) = rhs {
                    if lhsTheme !== rhsTheme {
                        return false
                    }
                    if lhsStrings !== rhsStrings {
                        return false
                    }
                    if lhsIndex != rhsIndex {
                        return false
                    }
                    if lhsParticipant != rhsParticipant {
                        return false
                    }
                    if lhsChecked != rhsChecked {
                        return false
                    }
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: ChatRecentActionsFilterEntry, rhs: ChatRecentActionsFilterEntry) -> Bool {
        switch lhs {
            case .actionsTitle:
                return true
            case .allActions:
                switch rhs {
                    case .actionsTitle:
                        return false
                    default:
                        return true
                }
            case let .actionItem(_, lhsIndex, _, _, _):
                switch rhs {
                    case .actionsTitle, .allActions:
                        return false
                    case let .actionItem(_, rhsIndex, _, _, _):
                        return lhsIndex < rhsIndex
                    default:
                        return true
                }
            case .adminsTitle:
                switch rhs {
                    case .adminPeerItem, .allAdmins:
                        return true
                    default:
                        return false
                }
            case .allAdmins:
                switch rhs {
                    case .adminPeerItem:
                        return true
                    default:
                        return false
                }
            case let .adminPeerItem(_, _, lhsIndex, _, _):
                switch rhs {
                    case let .adminPeerItem(_, _, rhsIndex, _, _):
                        return lhsIndex < rhsIndex
                    default:
                        return false
                }
        }
    }
    
    func item(_ arguments: ChatRecentActionsFilterControllerArguments) -> ListViewItem {
        switch self {
            case let .actionsTitle(theme, text):
                return ItemListSectionHeaderItem(theme: theme, text: text, sectionId: self.section)
            case let .allActions(theme, text, value):
                return ItemListSwitchItem(theme: theme, title: text, value: value, enabled: true, sectionId: self.section, style: .blocks, updated: { _ in
                    arguments.toggleAllActions()
                })
            case let .actionItem(theme, _, events, text, value):
                return ItemListCheckboxItem(theme: theme, title: text, style: .right, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.toggleAction(events)
                })
            case let .adminsTitle(theme, text):
                return ItemListSectionHeaderItem(theme: theme, text: text, sectionId: self.section)
            case let .allAdmins(theme, text, value):
                return ItemListSwitchItem(theme: theme, title: text, value: value, enabled: true, sectionId: self.section, style: .blocks, updated: { _ in
                    arguments.toggleAllAdmins()
                })
            case let .adminPeerItem(theme, strings, _, participant, checked):
                let peerText: String
                switch participant.participant {
                    case .creator:
                        peerText = strings.Channel_Management_LabelCreator
                    case .member:
                        peerText = strings.ChatAdmins_AdminLabel.capitalized
                }
                return ItemListPeerItem(theme: theme, strings: strings, account: arguments.account, peer: participant.peer, presence: nil, text: .text(peerText), label: .none, editing: ItemListPeerItemEditing(editable: false, editing: false, revealed: false), switchValue: ItemListPeerItemSwitch(value: checked, style: .check), enabled: true, sectionId: self.section, action: {
                    arguments.toggleAdmin(participant.peer.id)
                }, setPeerIdWithRevealedOptions: { _, _ in
                }, removePeer: { _ in })
        }
    }
}

private struct ChatRecentActionsFilterControllerState: Equatable {
    let events: AdminLogEventsFlags
    let adminPeerIds: [PeerId]?
    
    init(events: AdminLogEventsFlags, adminPeerIds: [PeerId]?) {
        self.events = events
        self.adminPeerIds = adminPeerIds
    }
    
    static func ==(lhs: ChatRecentActionsFilterControllerState, rhs: ChatRecentActionsFilterControllerState) -> Bool {
        if lhs.events != rhs.events {
            return false
        }
        if let lhsAdminPeerIds = lhs.adminPeerIds, let rhsAdminPeerIds = rhs.adminPeerIds {
            if lhsAdminPeerIds != rhsAdminPeerIds {
                return false
            }
        } else if (lhs.adminPeerIds != nil) != (rhs.adminPeerIds != nil) {
            return false
        }
        
        return true
    }
    
    func withUpdatedEvents(_ events: AdminLogEventsFlags) -> ChatRecentActionsFilterControllerState {
        return ChatRecentActionsFilterControllerState(events: events, adminPeerIds: self.adminPeerIds)
    }
    
    func withUpdatedAdminPeerIds(_ adminPeerIds: [PeerId]?) -> ChatRecentActionsFilterControllerState {
        return ChatRecentActionsFilterControllerState(events: self.events, adminPeerIds: adminPeerIds)
    }
}

private func channelRecentActionsFilterControllerEntries(presentationData: PresentationData, accountPeerId: PeerId, peer: Peer, state: ChatRecentActionsFilterControllerState, participants: [RenderedChannelParticipant]?) -> [ChatRecentActionsFilterEntry] {
    var isGroup = true
    if let peer = peer as? TelegramChannel, case .broadcast = peer.info {
        isGroup = false
    }
    
    var entries: [ChatRecentActionsFilterEntry] = []
    
    let order: [([AdminLogEventsFlags], String)]
    if isGroup {
        order = [
            ([.ban, .unban], presentationData.strings.Channel_AdminLogFilter_EventsRestrictions),
            ([.promote, .demote], presentationData.strings.Channel_AdminLogFilter_EventsAdmins),
            ([.invite, .join], presentationData.strings.Channel_AdminLogFilter_EventsNewMembers),
            ([.info], isGroup ? presentationData.strings.Channel_AdminLogFilter_EventsInfo : presentationData.strings.Channel_AdminLogFilter_ChannelEventsInfo),
            ([.deleteMessages], presentationData.strings.Channel_AdminLogFilter_EventsDeletedMessages),
            ([.editMessages], presentationData.strings.Channel_AdminLogFilter_EventsEditedMessages),
            ([.pinnedMessages], presentationData.strings.Channel_AdminLogFilter_EventsPinned),
            ([.leave], presentationData.strings.Channel_AdminLogFilter_EventsLeaving),
        ]
    } else {
        order = [
            ([.promote, .demote], presentationData.strings.Channel_AdminLogFilter_EventsAdmins),
            ([.invite, .join], presentationData.strings.Channel_AdminLogFilter_EventsNewMembers),
            ([.info], isGroup ? presentationData.strings.Channel_AdminLogFilter_EventsInfo : presentationData.strings.Channel_AdminLogFilter_ChannelEventsInfo),
            ([.deleteMessages], presentationData.strings.Channel_AdminLogFilter_EventsDeletedMessages),
            ([.editMessages], presentationData.strings.Channel_AdminLogFilter_EventsEditedMessages),
            ([.leave], presentationData.strings.Channel_AdminLogFilter_EventsLeaving),
        ]
    }
    
    var allTypesSelected = true
    outer: for (events, _) in order {
        for event in events {
            if !state.events.contains(event) {
                allTypesSelected = false
                break outer
            }
        }
    }
    
    entries.append(.actionsTitle(presentationData.theme, presentationData.strings.Channel_AdminLogFilter_EventsTitle))
    entries.append(.allActions(presentationData.theme, presentationData.strings.Channel_AdminLogFilter_EventsAll, allTypesSelected))
    
    var index: Int32 = 0
    for (events, text) in order {
        var eventsSelected = true
        inner: for event in events {
            if !state.events.contains(event) {
                eventsSelected = false
                break inner
            }
        }
        entries.append(.actionItem(presentationData.theme, index, events, text, eventsSelected))
        index += 1
    }
    
    if let participants = participants {
        var allAdminsSelected = true
        if let adminPeerIds = state.adminPeerIds {
            for participant in participants {
                if !adminPeerIds.contains(participant.peer.id) {
                    allAdminsSelected = false
                    break
                }
            }
        } else {
            allAdminsSelected = true
        }
        
        entries.append(.adminsTitle(presentationData.theme, presentationData.strings.Channel_AdminLogFilter_AdminsTitle))
        entries.append(.allAdmins(presentationData.theme, presentationData.strings.Channel_AdminLogFilter_AdminsAll, allAdminsSelected))
        
        var index: Int32 = 0
        for participant in participants {
            var adminSelected = true
            if let adminPeerIds = state.adminPeerIds {
                if !adminPeerIds.contains(participant.peer.id) {
                    adminSelected = false
                }
            } else {
                adminSelected = true
            }
            entries.append(.adminPeerItem(presentationData.theme, presentationData.strings, index, participant, adminSelected))
            index += 1
        }
    }
    
    return entries
}

public func channelRecentActionsFilterController(account: Account, peer: Peer, events: AdminLogEventsFlags, adminPeerIds: [PeerId]?, apply: @escaping (_ events: AdminLogEventsFlags, _ adminPeerIds: [PeerId]?) -> Void) -> ViewController {
    let statePromise = ValuePromise(ChatRecentActionsFilterControllerState(events: events, adminPeerIds: adminPeerIds), ignoreRepeated: true)
    let stateValue = Atomic(value: ChatRecentActionsFilterControllerState(events: events, adminPeerIds: adminPeerIds))
    let updateState: ((ChatRecentActionsFilterControllerState) -> ChatRecentActionsFilterControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
    var dismissImpl: (() -> Void)?
    
    let adminsPromise = Promise<[RenderedChannelParticipant]?>(nil)
    
    let presentationDataSignal = (account.applicationContext as! TelegramApplicationContext).presentationData
    
    let arguments = ChatRecentActionsFilterControllerArguments(account: account, toggleAllActions: {
        updateState { current in
            if current.events.isEmpty {
                return current.withUpdatedEvents(.all)
            } else {
                return current.withUpdatedEvents([])
            }
        }
    }, toggleAction: { events in
        if let first = events.first {
            updateState { current in
                var updatedEvents = current.events
                if updatedEvents.contains(first) {
                    for event in events {
                        updatedEvents.remove(event)
                    }
                } else {
                    for event in events {
                        updatedEvents.insert(event)
                    }
                }
                return current.withUpdatedEvents(updatedEvents)
            }
        }
    }, toggleAllAdmins: {
        let _ = (adminsPromise.get()
        |> take(1)
        |> deliverOnMainQueue).start(next: { admins in
            if let _ = admins {
                updateState { current in
                    if let _ = current.adminPeerIds {
                        return current.withUpdatedAdminPeerIds(nil)
                    } else {
                        return current.withUpdatedAdminPeerIds([])
                    }
                }
            }
        })
    }, toggleAdmin: { adminId in
        let _ = (adminsPromise.get()
            |> take(1)
            |> deliverOnMainQueue).start(next: { admins in
                if let admins = admins {
                    updateState { current in
                        if let adminPeerIds = current.adminPeerIds, let index = adminPeerIds.index(of: adminId) {
                            var updatedAdminPeerIds = adminPeerIds
                            updatedAdminPeerIds.remove(at: index)
                            return current.withUpdatedAdminPeerIds(updatedAdminPeerIds)
                        } else {
                            var updatedAdminPeerIds = current.adminPeerIds ?? admins.map { $0.peer.id }
                            if !updatedAdminPeerIds.contains(adminId) {
                                updatedAdminPeerIds.append(adminId)
                            }
                            return current.withUpdatedAdminPeerIds(updatedAdminPeerIds)
                        }
                    }
                }
            })
    })
    
    let adminsSignal: Signal<[RenderedChannelParticipant]?, NoError> = .single(nil) |> then(channelAdmins(account: account, peerId: peer.id) |> map { Optional($0) })
    
    adminsPromise.set(adminsSignal)
    
    var previousPeers: [RenderedChannelParticipant]?
    
    let signal = combineLatest(presentationDataSignal, statePromise.get(), adminsPromise.get() |> deliverOnMainQueue)
        |> deliverOnMainQueue
        |> map { presentationData, state, admins -> (ItemListControllerState, (ItemListNodeState<ChatRecentActionsFilterEntry>, ChatRecentActionsFilterEntry.ItemGenerationArguments)) in
            let leftNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
                dismissImpl?()
            })
            
            let doneEnabled = !state.events.isEmpty
            
            let rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: doneEnabled, action: {
                var resultState: ChatRecentActionsFilterControllerState?
                updateState { current in
                    resultState = current
                    return current
                }
                if let resultState = resultState {
                    apply(resultState.events, resultState.adminPeerIds)
                }
                dismissImpl?()
            })
            
            let previous = previousPeers
            previousPeers = admins
            
            let controllerState = ItemListControllerState(theme: presentationData.theme, title: .text(presentationData.strings.ChatAdmins_Title), leftNavigationButton: leftNavigationButton, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
            let listState = ItemListNodeState(entries: channelRecentActionsFilterControllerEntries(presentationData: presentationData, accountPeerId: account.peerId, peer: peer, state: state, participants: admins), style: .blocks, animateChanges: previous != nil && admins != nil && previous!.count >= admins!.count)
            
            return (controllerState, (listState, arguments))
        }
    
    let controller = ItemListController(account: account, state: signal)
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}
