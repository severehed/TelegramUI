import Foundation
import AsyncDisplayKit
import Display
import SwiftSignalKit

private let dotDiameter: CGFloat = 13.0
private let dotSpacing: CGFloat = 24.0
private let fieldHeight: CGFloat = 38.0

private func generateDotImage(color: UIColor, filled: Bool) -> UIImage? {
    return generateImage(CGSize(width: dotDiameter, height: dotDiameter), contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        
        if filled {
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: bounds)
        } else {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(1.0)
            context.strokeEllipse(in: bounds.insetBy(dx: 0.5, dy: 0.5))
        }
    })
}

private func generateFieldBackgroundImage(background: PasscodeBackground, frame: CGRect) -> UIImage? {
    return generateImage(frame.size, contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        
        let relativeFrame = CGRect(x: -frame.minX, y: frame.minY - background.size.height + frame.size.height
            , width: background.size.width, height: background.size.height)
        
        let path = UIBezierPath(roundedRect: CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height), cornerRadius: 6.0)
        context.addPath(path.cgPath)
        context.clip()
        
        context.draw(background.foregroundImage.cgImage!, in: relativeFrame)
        
        context.setBlendMode(.clear)
        context.setFillColor(UIColor.clear.cgColor)
    
        let innerPath = UIBezierPath(roundedRect: CGRect(x: 1.0, y: 1.0, width: size.width - 2.0, height: size.height - 2.0), cornerRadius: 6.0)
        context.addPath(innerPath.cgPath)
        context.fillPath()
    })
}

enum PasscodeEntryFieldType {
    case digits6
    case digits4
    case alphanumeric
    
    var maxLength: Int? {
        switch self {
            case .digits6:
                return 6
            case .digits4:
                return 4
            case .alphanumeric:
                return nil
        }
    }
    
    var allowedCharacters: CharacterSet? {
        switch self {
            case .digits6, .digits4:
                return CharacterSet.decimalDigits
            case .alphanumeric:
                return nil
        }
    }
}

private class PasscodeEntryInputView: UIView {
    
}

private class PasscodeEntryDotNode: ASImageNode {
    private let regularImage: UIImage
    private let filledImage: UIImage
    private var currentImage: UIImage
    
    init(color: UIColor) {
        self.regularImage = generateDotImage(color: color, filled: false)!
        self.filledImage = generateDotImage(color: color, filled: true)!
        self.currentImage = self.regularImage
        
        super.init()
        
        self.image = self.currentImage
    }
    
    func updateState(filled: Bool, animated: Bool = false, delay: Double = 0.0) {
        let image = filled ? self.filledImage : self.regularImage
        if self.currentImage !== image {
            let currentContents = self.layer.contents
            self.layer.removeAnimation(forKey: "contents")
            if let currentContents = currentContents, animated {
                self.image = image
                self.layer.animate(from: currentContents as AnyObject, to: image.cgImage!, keyPath: "contents", timingFunction: kCAMediaTimingFunctionEaseOut, duration: image === self.regularImage ? 0.25 : 0.05, delay: delay)
            } else {
                self.image = image
            }
            self.currentImage = image
        }
    }
}

final class PasscodeEntryInputFieldNode: ASDisplayNode, UITextFieldDelegate {
    private var background: PasscodeBackground?
    private var color: UIColor
    private var fieldType: PasscodeEntryFieldType
    
    private let textFieldNode: TextFieldNode
    private let borderNode: ASImageNode
    private let dotNodes: [PasscodeEntryDotNode]
    
    private var validLayout: ContainerViewLayout?
    
    var complete: ((String) -> Void)?
    
    init(color: UIColor, fieldType: PasscodeEntryFieldType) {
        self.color = color
        self.fieldType = fieldType
        
        self.textFieldNode = TextFieldNode()
        self.borderNode = ASImageNode()
        self.dotNodes = (0 ..< 6).map { _ in PasscodeEntryDotNode(color: color) }
        
        super.init()
        
        self.isUserInteractionEnabled = false
        
        for node in self.dotNodes {
            self.addSubnode(node)
        }
        self.addSubnode(self.textFieldNode)
        self.addSubnode(self.borderNode)
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.textFieldNode.textField.isSecureTextEntry = true
        self.textFieldNode.textField.textColor = .white
        self.textFieldNode.textField.delegate = self
        self.textFieldNode.textField.returnKeyType = .done
        self.textFieldNode.textField.tintColor = .white
        self.textFieldNode.textField.keyboardAppearance = .dark
        
        switch self.fieldType {
            case .digits6, .digits4:
                self.textFieldNode.textField.inputView = PasscodeEntryInputView()
            case .alphanumeric:
                break
        }
    }
    
    func updateBackground(_ background: PasscodeBackground) {
        self.background = background
        if let validLayout = self.validLayout {
            let _ = self.updateLayout(layout: validLayout, transition: .immediate)
        }
    }
    
    func activateInput() {
        self.textFieldNode.textField.becomeFirstResponder()
    }
    
    func animateIn() {
        switch self.fieldType {
            case .digits6, .digits4:
                for node in self.dotNodes {
                    node.layer.animateScale(from: 0.0001, to: 1.0, duration: 0.25, timingFunction: kCAMediaTimingFunctionEaseOut)
                }
            case .alphanumeric:
                self.textFieldNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25, timingFunction: kCAMediaTimingFunctionEaseOut)
                self.borderNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25, timingFunction: kCAMediaTimingFunctionEaseOut)
        }
    }
    
    func reset() {
        var delay: Double = 0.0
        for node in self.dotNodes.reversed() {
            if node.alpha < 1.0 {
                continue
            }
            
            node.updateState(filled: false, animated: true, delay: delay)
            delay += 0.05
        }
        self.textFieldNode.textField.text = ""
    }
    
    func append(_ string: String) {
        var text = (self.textFieldNode.textField.text ?? "") + string
        let maxLength = self.fieldType.maxLength
        if let maxLength = maxLength, text.count > maxLength {
            return
        }
        self.textFieldNode.textField.text = text
        
        text = self.textFieldNode.textField.text ?? "" + string
        self.updateDots(count: text.count, animated: false)
        
        if let maxLength = maxLength, text.count == maxLength {
            Queue.mainQueue().after(0.2) {
                self.complete?(text)
            }
        }
    }
    
    func delete() {
        var text = self.textFieldNode.textField.text ?? ""
        guard !text.isEmpty else {
            return
        }
        text = String(text[text.startIndex ..< text.index(text.endIndex, offsetBy: -1)])
        self.textFieldNode.textField.text = text
        self.updateDots(count: text.count, animated: true)
    }
    
    func updateDots(count: Int, animated: Bool) {
        var i = -1
        for node in self.dotNodes {
            if node.alpha < 1.0 {
                continue
            }
            i += 1
            node.updateState(filled: i < count, animated: animated)
        }
    }
    
    func update(fieldType: PasscodeEntryFieldType) {
        if fieldType != self.fieldType {
            self.textFieldNode.textField.text = ""
        }
        self.fieldType = fieldType
        if let validLayout = self.validLayout {
            let _ = self.updateLayout(layout: validLayout, transition: .immediate)
        }
    }
    
    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) -> CGRect {
        self.validLayout = layout
        
        switch self.fieldType {
            case .digits6:
                self.textFieldNode.alpha = 0.0
                self.borderNode.alpha = 0.0
            case .digits4:
                self.textFieldNode.alpha = 0.0
                self.borderNode.alpha = 0.0
            case .alphanumeric:
                self.textFieldNode.alpha = 1.0
                self.borderNode.alpha = 1.0
        }
        
        let origin = CGPoint(x: floor((layout.size.width - dotDiameter * 6 - dotSpacing * 5) / 2.0), y: 164.0)
        for i in 0 ..< self.dotNodes.count {
            let node = self.dotNodes[i]
            switch self.fieldType {
                case .digits6:
                    node.alpha = 1.0
                case .digits4:
                    node.alpha = (i > 0 && i < self.dotNodes.count - 1) ? 1.0 : 0.0
                case .alphanumeric:
                    node.alpha = 0.0
            }
            
            let dotFrame = CGRect(x: origin.x + CGFloat(i) * (dotDiameter + dotSpacing), y: origin.y, width: dotDiameter, height: dotDiameter)
            transition.updateFrame(node: node, frame: dotFrame)
        }
        
        let inset: CGFloat = 50.0
        let fieldFrame = CGRect(x: inset, y: origin.y, width: layout.size.width - inset * 2.0, height: fieldHeight)
        transition.updateFrame(node: self.borderNode, frame: fieldFrame)
        transition.updateFrame(node: self.textFieldNode, frame: fieldFrame.insetBy(dx: 13.0, dy: 0.0))
        if let background = self.background {
            self.borderNode.image = generateFieldBackgroundImage(background: background, frame: fieldFrame)
        }
        
        return fieldFrame
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let currentText = textField.text ?? ""
        let text = (currentText as NSString).replacingCharacters(in: range, with: string)
        if let maxLength = self.fieldType.maxLength, text.count > maxLength {
            return false
        }
        if let allowedCharacters = self.fieldType.allowedCharacters, let _ = text.rangeOfCharacter(from: allowedCharacters.inverted) {
            return false
        }
        self.updateDots(count: text.count, animated: text.count < currentText.count)
        
        if string == "\n" {
            Queue.mainQueue().after(0.2) {
                self.complete?(currentText)
            }
            return false
        }
        
        if let maxLength = self.fieldType.maxLength, text.count == maxLength {
            Queue.mainQueue().after(0.2) {
                self.complete?(text)
            }
        }
        return true
    }
}
