import Foundation
import SwiftSignalKit
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore

private final class CallRatingContentActionNode: HighlightableButtonNode {
    private let backgroundNode: ASDisplayNode
    
    let action: TextAlertAction
    
    init(theme: AlertControllerTheme, action: TextAlertAction) {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.alpha = 0.0
        
        self.action = action
        
        super.init()
        
        self.titleNode.maximumNumberOfLines = 2
        
        self.highligthedChanged = { [weak self] value in
            if let strongSelf = self {
                if value {
                    if strongSelf.backgroundNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                    }
                    strongSelf.backgroundNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.backgroundNode.alpha = 1.0
                } else if !strongSelf.backgroundNode.alpha.isZero {
                    strongSelf.backgroundNode.alpha = 0.0
                    strongSelf.backgroundNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25)
                }
            }
        }
        
        self.updateTheme(theme)
    }
    
    func updateTheme(_ theme: AlertControllerTheme) {
        self.backgroundNode.backgroundColor = theme.highlightedItemColor
        
        var font = Font.regular(17.0)
        var color = theme.accentColor
        switch self.action.type {
        case .defaultAction, .genericAction:
            break
        case .destructiveAction:
            color = theme.destructiveColor
        }
        switch self.action.type {
        case .defaultAction:
            font = Font.semibold(17.0)
        case .destructiveAction, .genericAction:
            break
        }
        self.setAttributedTitle(NSAttributedString(string: self.action.title, font: font, textColor: color, paragraphAlignment: .center), for: [])
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.addTarget(self, action: #selector(self.pressed), forControlEvents: .touchUpInside)
    }
    
    @objc func pressed() {
        self.action.action()
    }
    
    override func layout() {
        super.layout()
        
        self.backgroundNode.frame = self.bounds
    }
}

private final class CallRatingAlertContentNode: AlertContentNode {
    private var validLayout: CGSize?
    private let strings: PresentationStrings
    
    var rating: Int?
    
    private let titleNode: ASTextNode
    private let starNodes: [ASButtonNode]
    private let inputFieldNode: ShareInputFieldNode
    
    private let actionNodesSeparator: ASDisplayNode
    private let actionNodes: [CallRatingContentActionNode]
    private let actionVerticalSeparators: [ASDisplayNode]
    
    private let disposable = MetaDisposable()
    
    override var dismissOnOutsideTap: Bool {
        return self.isUserInteractionEnabled
    }
    
    init(theme: AlertControllerTheme, ptheme: PresentationTheme, strings: PresentationStrings, actions: [TextAlertAction], dismiss: @escaping () -> Void) {
        self.strings = strings
        
        self.titleNode = ASTextNode()
        self.titleNode.maximumNumberOfLines = 2
        
        var starNodes: [ASButtonNode] = []
        for _ in 0 ..< 5 {
            starNodes.append(ASButtonNode())
        }
        self.starNodes = starNodes
        
        self.inputFieldNode = ShareInputFieldNode(theme: ShareInputFieldNodeTheme(presentationTheme: ptheme), placeholder: strings.Calls_RatingFeedback)
        self.inputFieldNode.alpha = 0.0
        
        self.actionNodesSeparator = ASDisplayNode()
        self.actionNodesSeparator.isLayerBacked = true
        
        self.actionNodes = actions.map { action -> CallRatingContentActionNode in
            return CallRatingContentActionNode(theme: theme, action: action)
        }
        
        var actionVerticalSeparators: [ASDisplayNode] = []
        if actions.count > 1 {
            for _ in 0 ..< actions.count - 1 {
                let separatorNode = ASDisplayNode()
                separatorNode.isLayerBacked = true
                actionVerticalSeparators.append(separatorNode)
            }
        }
        self.actionVerticalSeparators = actionVerticalSeparators
        
        super.init()
        
        self.addSubnode(self.titleNode)
        
        for node in self.starNodes {
            node.addTarget(self, action: #selector(self.starPressed(_:)), forControlEvents: .touchUpInside)
            self.addSubnode(node)
        }
        
        self.addSubnode(self.inputFieldNode)
        
        self.addSubnode(self.actionNodesSeparator)
        
        for actionNode in self.actionNodes {
            self.addSubnode(actionNode)
        }
        
        for separatorNode in self.actionVerticalSeparators {
            self.addSubnode(separatorNode)
        }
        
        self.inputFieldNode.updateHeight = { [weak self] in
            if let strongSelf = self {
                if let _ = strongSelf.validLayout {
                    strongSelf.requestLayout?(.animated(duration: 0.15, curve: .spring))
                }
            }
        }
        
        self.updateTheme(theme)
    }
    
    deinit {
        self.disposable.dispose()
    }
    
    var comment: String {
        return self.inputFieldNode.text
    }
    
    @objc func starPressed(_ sender: ASButtonNode) {
        if let index = self.starNodes.firstIndex(of: sender) {
            self.rating = index + 1
            for i in 0 ..< self.starNodes.count {
                let node = self.starNodes[i]
                node.isSelected = i <= index
            }
            if index < 3 {
                self.inputFieldNode.placeholder = self.strings.Call_ReportPlaceholder
            } else {
                self.inputFieldNode.placeholder = self.strings.Calls_RatingFeedback
            }
            self.requestLayout?(.animated(duration: 0.3, curve: .spring))
        }
    }
    
    override func updateTheme(_ theme: AlertControllerTheme) {
        self.titleNode.attributedText = NSAttributedString(string: strings.Calls_RatingTitle, font: Font.bold(17.0), textColor: theme.primaryColor, paragraphAlignment: .center)
        
        for node in self.starNodes {
            node.setImage(generateTintedImage(image: UIImage(bundleImageName: "Call/Star"), color: theme.accentColor), for: [])
            let highlighted = generateTintedImage(image: UIImage(bundleImageName: "Call/StarHighlighted"), color: theme.accentColor)
            node.setImage(highlighted, for: [.selected])
            node.setImage(highlighted, for: [.selected, .highlighted])
        }
        
        self.actionNodesSeparator.backgroundColor = theme.separatorColor
        for actionNode in self.actionNodes {
            actionNode.updateTheme(theme)
        }
        for separatorNode in self.actionVerticalSeparators {
            separatorNode.backgroundColor = theme.separatorColor
        }
        
        if let size = self.validLayout {
            _ = self.updateLayout(size: size, transition: .immediate)
        }
    }
    
    override func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        var size = size
        size.width = min(size.width , 270.0)
        
        self.validLayout = size
        
        var origin: CGPoint = CGPoint(x: 0.0, y: 20.0)
        
        let titleSize = self.titleNode.measure(size)
        transition.updateFrame(node: self.titleNode, frame: CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - titleSize.width) / 2.0), y: origin.y), size: titleSize))
        origin.y += titleSize.height + 13.0
        
        let actionButtonHeight: CGFloat = 44.0
        var minActionsWidth: CGFloat = 0.0
        let maxActionWidth: CGFloat = floor(size.width / CGFloat(self.actionNodes.count))
        let actionTitleInsets: CGFloat = 8.0
        
        var effectiveActionLayout = TextAlertContentActionLayout.horizontal
        for actionNode in self.actionNodes {
            let actionTitleSize = actionNode.titleNode.measure(CGSize(width: maxActionWidth, height: actionButtonHeight))
            if case .horizontal = effectiveActionLayout, actionTitleSize.height > actionButtonHeight * 0.6667 {
                effectiveActionLayout = .vertical
            }
            switch effectiveActionLayout {
            case .horizontal:
                minActionsWidth += actionTitleSize.width + actionTitleInsets
            case .vertical:
                minActionsWidth = max(minActionsWidth, actionTitleSize.width + actionTitleInsets)
            }
        }
        
        let insets = UIEdgeInsets(top: 18.0, left: 18.0, bottom: 18.0, right: 18.0)
        
        var contentWidth = max(titleSize.width, minActionsWidth)
        contentWidth = max(contentWidth, 234.0)
        
        var actionsHeight: CGFloat = 0.0
        switch effectiveActionLayout {
            case .horizontal:
                actionsHeight = actionButtonHeight
            case .vertical:
                actionsHeight = actionButtonHeight * CGFloat(self.actionNodes.count)
        }
        
        let resultWidth = contentWidth + insets.left + insets.right
        
        let starSize = CGSize(width: 42.0, height: 38.0)
        let starsOrigin = floorToScreenPixels((resultWidth - starSize.width * 5.0) / 2.0)
        for i in 0 ..< self.starNodes.count {
            let node = self.starNodes[i]
            transition.updateFrame(node: node, frame: CGRect(x: starsOrigin + 42.0 * CGFloat(i), y: origin.y, width: starSize.width, height: starSize.height))
        }
        origin.y += titleSize.height
        
        let inputFieldWidth = resultWidth
        let inputFieldHeight = self.inputFieldNode.updateLayout(width: inputFieldWidth, transition: transition)
        var inputHeight: CGFloat = 0.0
        if let rating = rating, rating < 5 {
            inputHeight += inputFieldHeight
        }
        transition.updateFrame(node: self.inputFieldNode, frame: CGRect(x: 0.0, y: origin.y, width: resultWidth, height: inputFieldHeight))
        transition.updateAlpha(node: self.inputFieldNode, alpha: inputHeight > 0.0 ? 1.0 : 0.0)
        
        let resultSize = CGSize(width: resultWidth, height: titleSize.height + actionsHeight + 56.0 + inputHeight + insets.top + insets.bottom)
        
        transition.updateFrame(node: self.actionNodesSeparator, frame: CGRect(origin: CGPoint(x: 0.0, y: resultSize.height - actionsHeight - UIScreenPixel), size: CGSize(width: resultSize.width, height: UIScreenPixel)))
        
        var actionOffset: CGFloat = 0.0
        let actionWidth: CGFloat = floor(resultSize.width / CGFloat(self.actionNodes.count))
        var separatorIndex = -1
        var nodeIndex = 0
        for actionNode in self.actionNodes {
            if separatorIndex >= 0 {
                let separatorNode = self.actionVerticalSeparators[separatorIndex]
                switch effectiveActionLayout {
                case .horizontal:
                    transition.updateFrame(node: separatorNode, frame: CGRect(origin: CGPoint(x: actionOffset - UIScreenPixel, y: resultSize.height - actionsHeight), size: CGSize(width: UIScreenPixel, height: actionsHeight - UIScreenPixel)))
                case .vertical:
                    transition.updateFrame(node: separatorNode, frame: CGRect(origin: CGPoint(x: 0.0, y: resultSize.height - actionsHeight + actionOffset - UIScreenPixel), size: CGSize(width: resultSize.width, height: UIScreenPixel)))
                }
            }
            separatorIndex += 1
            
            let currentActionWidth: CGFloat
            switch effectiveActionLayout {
            case .horizontal:
                if nodeIndex == self.actionNodes.count - 1 {
                    currentActionWidth = resultSize.width - actionOffset
                } else {
                    currentActionWidth = actionWidth
                }
            case .vertical:
                currentActionWidth = resultSize.width
            }
            
            let actionNodeFrame: CGRect
            switch effectiveActionLayout {
                case .horizontal:
                    actionNodeFrame = CGRect(origin: CGPoint(x: actionOffset, y: resultSize.height - actionsHeight), size: CGSize(width: currentActionWidth, height: actionButtonHeight))
                    actionOffset += currentActionWidth
                case .vertical:
                    actionNodeFrame = CGRect(origin: CGPoint(x: 0.0, y: resultSize.height - actionsHeight + actionOffset), size: CGSize(width: currentActionWidth, height: actionButtonHeight))
                    actionOffset += actionButtonHeight
            }
            
            transition.updateFrame(node: actionNode, frame: actionNodeFrame)
            
            nodeIndex += 1
        }
        
        return resultSize
    }
}

private func rateCallAndSendLogs(account: Account, report: ReportCallRating, starsCount: Int, comment: String, includeLogs: Bool) -> Signal<Void, NoError> {
    var signal = rateCall(account: account, report: report, starsCount: Int32(starsCount), comment: comment)
    if includeLogs {
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: 4244000)
//        signal = signal
//        |> then(
//            enqueueMessages(account: account, peerId: peerId, messages: EnqueueMessage.message(text: "", attributes: [], mediaReference: nil, replyToMessageId: nil, localGroupingKey: nil))
//            |> map { _ -> Void in
//                    
//            }
//        )
    }
    return signal
}

func callRatingController(account: Account, report: ReportCallRating, present: @escaping (ViewController) -> Void) -> AlertController {
    let presentationData = account.telegramApplicationContext.currentPresentationData.with { $0 }
    let theme = presentationData.theme
    let strings = presentationData.strings
    
    var dismissImpl: ((Bool) -> Void)?
    var contentNode: CallRatingAlertContentNode?
    let actions: [TextAlertAction] = [TextAlertAction(type: .genericAction, title: presentationData.strings.Common_NotNow, action: {
        dismissImpl?(true)
    }), TextAlertAction(type: .defaultAction, title: presentationData.strings.Calls_SubmitRating, action: {
        dismissImpl?(true)
        if let contentNode = contentNode, let rating = contentNode.rating {
            if rating < 4 {
                let controller = textAlertController(account: account, title: strings.Call_ReportIncludeLog, text: strings.Call_ReportIncludeLogDescription, actions: [TextAlertAction(type: .genericAction, title: presentationData.strings.Call_ReportSkip, action: {
                    let _ = rateCallAndSendLogs(account: account, report: report, starsCount: rating, comment: contentNode.comment, includeLogs: false).start()
                }), TextAlertAction(type: .defaultAction, title: presentationData.strings.Call_ReportSend, action: {
                    let _ = rateCallAndSendLogs(account: account, report: report, starsCount: rating, comment: contentNode.comment, includeLogs: true).start()
                })])
                present(controller)
            } else {
                let _ = rateCallAndSendLogs(account: account, report: report, starsCount: rating, comment: contentNode.comment, includeLogs: false).start
            }
        }
    })]
    
    contentNode = CallRatingAlertContentNode(theme: AlertControllerTheme(presentationTheme: theme), ptheme: theme, strings: strings, actions: actions, dismiss: {
        dismissImpl?(true)
    })
    
    let controller = AlertController(theme: AlertControllerTheme(presentationTheme: theme), contentNode: contentNode!)
    dismissImpl = { [weak controller] animated in
        if animated {
            controller?.dismissAnimated()
        } else {
            controller?.dismiss()
        }
    }
    return controller
}
