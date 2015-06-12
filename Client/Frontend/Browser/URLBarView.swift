/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import Shared
import SnapKit

private struct URLBarViewUX {
    // The color shown behind the tabs count button, and underneath the (mostly transparent) status bar.
    static let TextFieldBorderColor = UIColor.blackColor().colorWithAlphaComponent(0.05)
    static let TextFieldActiveBorderColor = UIColor(rgb: 0x4A90E2)
    static let LocationLeftPadding = 5
    static let LocationHeight = 30
    static let TextFieldCornerRadius: CGFloat = 3
    static let TextFieldBorderWidth: CGFloat = 1
    // offset from edge of tabs button
    static let URLBarCurveOffset: CGFloat = 14
    // buffer so we dont see edges when animation overshoots with spring
    static let URLBarCurveBounceBuffer: CGFloat = 8

    static let TabsButtonRotationOffset: CGFloat = 1.5
    static let TabsButtonHeight: CGFloat = 18.0
    static let ToolbarButtonInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

    static func backgroundColorWithAlpha(alpha: CGFloat) -> UIColor {
        return AppConstants.AppBackgroundColor.colorWithAlphaComponent(alpha)
    }
}

protocol URLBarDelegate: class {
    func urlBarDidPressTabs(urlBar: URLBarView)
    func urlBarDidPressReaderMode(urlBar: URLBarView)
    func urlBarDidLongPressReaderMode(urlBar: URLBarView)
    func urlBarDidPressStop(urlBar: URLBarView)
    func urlBarDidPressReload(urlBar: URLBarView)
    func urlBarDidBeginEditing(urlBar: URLBarView)
    func urlBarDidEndEditing(urlBar: URLBarView)
    func urlBarDidLongPressLocation(urlBar: URLBarView)
    func urlBar(urlBar: URLBarView, didEnterText text: String)
    func urlBar(urlBar: URLBarView, didSubmitText text: String)
}

class URLBarView: UIView {
    weak var delegate: URLBarDelegate?
    weak var browserToolbarDelegate: BrowserToolbarDelegate?
    var helper: BrowserToolbarHelper?

    var toolbarIsShowing = false

    var backButtonLeftConstraint: Constraint?

    private lazy var locationView: BrowserLocationView = {
        var locationView = BrowserLocationView(frame: CGRectZero)
        locationView.setTranslatesAutoresizingMaskIntoConstraints(false)
        locationView.readerModeState = ReaderModeState.Unavailable
        locationView.delegate = self
        return locationView
    }()

    private lazy var editTextField: ToolbarTextField = {
        var editTextField = ToolbarTextField()
        editTextField.keyboardType = UIKeyboardType.WebSearch
        editTextField.autocorrectionType = UITextAutocorrectionType.No
        editTextField.autocapitalizationType = UITextAutocapitalizationType.None
        editTextField.returnKeyType = UIReturnKeyType.Go
        editTextField.clearButtonMode = UITextFieldViewMode.WhileEditing
        editTextField.layer.backgroundColor = UIColor.whiteColor().CGColor
        editTextField.autocompleteDelegate = self
        editTextField.font = AppConstants.DefaultMediumFont
        editTextField.layer.cornerRadius = URLBarViewUX.TextFieldCornerRadius
        editTextField.layer.borderColor = URLBarViewUX.TextFieldActiveBorderColor.CGColor
        editTextField.layer.borderWidth = 1
        editTextField.hidden = true
        editTextField.accessibilityLabel = NSLocalizedString("Address and Search", comment: "Accessibility label for address and search field, both words (Address, Search) are therefore nouns.")
        editTextField.attributedPlaceholder = BrowserLocationView.PlaceholderText
        return editTextField
    }()

    private lazy var locationContainer: UIView = {
        var locationContainer = UIView()
        locationContainer.setTranslatesAutoresizingMaskIntoConstraints(false)
        locationContainer.layer.borderColor = URLBarViewUX.TextFieldBorderColor.CGColor
        locationContainer.layer.cornerRadius = URLBarViewUX.TextFieldCornerRadius
        locationContainer.layer.borderWidth = URLBarViewUX.TextFieldBorderWidth
        return locationContainer
    }()

    private lazy var tabsButton: UIButton = {
        var tabsButton = InsetButton()
        tabsButton.setTranslatesAutoresizingMaskIntoConstraints(false)
        tabsButton.setTitle("0", forState: UIControlState.Normal)
        tabsButton.setTitleColor(URLBarViewUX.backgroundColorWithAlpha(1), forState: UIControlState.Normal)
        tabsButton.titleLabel?.layer.backgroundColor = UIColor.whiteColor().CGColor
        tabsButton.titleLabel?.layer.cornerRadius = 2
        tabsButton.titleLabel?.font = AppConstants.DefaultSmallFontBold
        tabsButton.titleLabel?.textAlignment = NSTextAlignment.Center
        tabsButton.setContentHuggingPriority(1000, forAxis: UILayoutConstraintAxis.Horizontal)
        tabsButton.setContentCompressionResistancePriority(1000, forAxis: UILayoutConstraintAxis.Horizontal)
        tabsButton.addTarget(self, action: "SELdidClickAddTab", forControlEvents: UIControlEvents.TouchUpInside)
        tabsButton.accessibilityLabel = NSLocalizedString("Show Tabs", comment: "Accessibility Label for the tabs button in the browser toolbar")
        return tabsButton
    }()

    private lazy var progressBar: UIProgressView = {
        var progressBar = UIProgressView()
        progressBar.progressTintColor = UIColor(red:1, green:0.32, blue:0, alpha:1)
        progressBar.alpha = 0
        progressBar.hidden = true
        return progressBar
    }()

    private lazy var cancelButton: UIButton = {
        var cancelButton = InsetButton()
        cancelButton.setTitleColor(UIColor.blackColor(), forState: UIControlState.Normal)
        let cancelTitle = NSLocalizedString("Cancel", comment: "Button label to cancel entering a URL or search query")
        cancelButton.setTitle(cancelTitle, forState: UIControlState.Normal)
        cancelButton.titleLabel?.font = AppConstants.DefaultMediumFont
        cancelButton.addTarget(self, action: "SELdidClickCancel", forControlEvents: UIControlEvents.TouchUpInside)
        cancelButton.titleEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12)
        cancelButton.setContentHuggingPriority(1000, forAxis: UILayoutConstraintAxis.Horizontal)
        cancelButton.setContentCompressionResistancePriority(1000, forAxis: UILayoutConstraintAxis.Horizontal)
        return cancelButton
    }()

    private lazy var curveShape: CurveView = { return CurveView() }()

    lazy var shareButton: UIButton = { return UIButton() }()

    lazy var bookmarkButton: UIButton = { return UIButton() }()

    lazy var forwardButton: UIButton = { return UIButton() }()

    lazy var backButton: UIButton = { return UIButton() }()

    lazy var stopReloadButton: UIButton = { return UIButton() }()

    lazy var actionButtons: [UIButton] = {
        return [self.shareButton, self.bookmarkButton, self.forwardButton, self.backButton, self.stopReloadButton]
    }()

    // Used to temporarily store the cloned button so we can respond to layout changes during animation
    private weak var clonedTabsButton: InsetButton?

    var isEditing: Bool {
        return !editTextField.hidden
    }

    var currentURL: NSURL? {
        get {
            return locationView.url
        }
        set(newURL) {
            locationView.url = newURL
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = URLBarViewUX.backgroundColorWithAlpha(0)
        addSubview(curveShape);

        locationContainer.addSubview(locationView)
        locationContainer.addSubview(editTextField)
        addSubview(locationContainer)

        addSubview(progressBar)
        addSubview(tabsButton)
        addSubview(cancelButton)

        addSubview(shareButton)
        addSubview(bookmarkButton)
        addSubview(forwardButton)
        addSubview(backButton)
        addSubview(stopReloadButton)

        helper = BrowserToolbarHelper(toolbar: self)
        setupConstraints()

        // Make sure we hide any views that shouldn't be showing in non-editing mode
        finishEditingAnimation(false)
    }

    private func setupConstraints() {
        progressBar.snp_makeConstraints { make in
            make.top.equalTo(self.snp_bottom)
            make.width.equalTo(self)
        }

        locationView.snp_makeConstraints { make in
            make.edges.equalTo(self.locationContainer).insets(EdgeInsetsMake(URLBarViewUX.TextFieldBorderWidth,
                URLBarViewUX.TextFieldBorderWidth,
                URLBarViewUX.TextFieldBorderWidth,
                URLBarViewUX.TextFieldBorderWidth))
        }

        editTextField.snp_makeConstraints { make in
            make.edges.equalTo(self.locationContainer)
        }

        cancelButton.snp_makeConstraints { make in
            make.centerY.equalTo(self.locationContainer)
            make.trailing.equalTo(self)
        }

        tabsButton.titleLabel?.snp_makeConstraints { make in
            make.size.equalTo(URLBarViewUX.TabsButtonHeight)
        }
    }

    private func updateToolbarConstraints() {
        if toolbarIsShowing {
            backButton.snp_remakeConstraints { (make) -> () in
                self.backButtonLeftConstraint = make.left.equalTo(self).constraint
                make.centerY.equalTo(self)
                make.size.equalTo(AppConstants.ToolbarHeight)
            }
            backButton.contentEdgeInsets = URLBarViewUX.ToolbarButtonInsets

            forwardButton.snp_remakeConstraints { (make) -> () in
                make.left.equalTo(self.backButton.snp_right)
                make.centerY.equalTo(self)
                make.size.equalTo(AppConstants.ToolbarHeight)
            }
            forwardButton.contentEdgeInsets = URLBarViewUX.ToolbarButtonInsets

            stopReloadButton.snp_remakeConstraints { (make) -> () in
                make.left.equalTo(self.forwardButton.snp_right)
                make.centerY.equalTo(self)
                make.size.equalTo(AppConstants.ToolbarHeight)
            }
            stopReloadButton.contentEdgeInsets = URLBarViewUX.ToolbarButtonInsets

            shareButton.snp_remakeConstraints { (make) -> () in
                make.right.equalTo(self.bookmarkButton.snp_left)
                make.centerY.equalTo(self)
                make.size.equalTo(AppConstants.ToolbarHeight)
            }

            bookmarkButton.snp_remakeConstraints { (make) -> () in
                make.right.equalTo(self.tabsButton.snp_left)
                make.centerY.equalTo(self)
                make.size.equalTo(AppConstants.ToolbarHeight)
            }
        }
    }

    override func updateConstraints() {
        updateToolbarConstraints()

        tabsButton.snp_remakeConstraints { make in
            make.centerY.equalTo(self.locationContainer)
            make.trailing.equalTo(self)
            make.width.height.equalTo(AppConstants.ToolbarHeight)
        }

        // Add an offset to the left for slide animation, and a bit of extra offset for spring bounces
        let leftOffset: CGFloat = self.tabsButton.frame.width + URLBarViewUX.URLBarCurveOffset + URLBarViewUX.URLBarCurveBounceBuffer
        self.curveShape.snp_remakeConstraints { make in
            make.edges.equalTo(self).offset(EdgeInsetsMake(0, -leftOffset, 0, URLBarViewUX.URLBarCurveBounceBuffer))
        }

        updateLayoutForEditing(editing: isEditing, animated: false)
        super.updateConstraints()
    }

    // Ideally we'd split this implementation in two, one URLBarView with a toolbar and one without
    // However, switching views dynamically at runtime is a difficult. For now, we just use one view
    // that can show in either mode.
    func setShowToolbar(shouldShow: Bool) {
        toolbarIsShowing = shouldShow
        setNeedsUpdateConstraints()
    }

    func updateURLBarText(text: String) {
        delegate?.urlBarDidBeginEditing(self)

        editTextField.text = text
        editTextField.becomeFirstResponder()

        updateLayoutForEditing(editing: true)

        delegate?.urlBar(self, didEnterText: text)
    }

    func updateAlphaForSubviews(alpha: CGFloat) {
        self.tabsButton.alpha = alpha
        self.locationContainer.alpha = alpha
        self.backgroundColor = URLBarViewUX.backgroundColorWithAlpha(1 - alpha)
        self.actionButtons.map { $0.alpha = alpha }
    }

    func updateTabCount(count: Int) {
        // make a 'clone' of the tabs button
        let newTabsButton = InsetButton()
        self.clonedTabsButton = newTabsButton
        newTabsButton.addTarget(self, action: "SELdidClickAddTab", forControlEvents: UIControlEvents.TouchUpInside)
        newTabsButton.setTitleColor(AppConstants.AppBackgroundColor, forState: UIControlState.Normal)
        newTabsButton.titleLabel?.layer.backgroundColor = UIColor.whiteColor().CGColor
        newTabsButton.titleLabel?.layer.cornerRadius = 2
        newTabsButton.titleLabel?.font = AppConstants.DefaultSmallFontBold
        newTabsButton.titleLabel?.textAlignment = NSTextAlignment.Center
        newTabsButton.setTitle(count.description, forState: .Normal)
        addSubview(newTabsButton)
        newTabsButton.titleLabel?.snp_makeConstraints { make in
            make.size.equalTo(URLBarViewUX.TabsButtonHeight)
        }
        newTabsButton.snp_makeConstraints { make in
            make.centerY.equalTo(self.locationContainer)
            make.trailing.equalTo(self)
            make.size.equalTo(AppConstants.ToolbarHeight)
        }

        newTabsButton.frame = tabsButton.frame

        // Instead of changing the anchorPoint of the CALayer, lets alter the rotation matrix math to be
        // a rotation around a non-origin point
        if let labelFrame = newTabsButton.titleLabel?.frame {
            let halfTitleHeight = CGRectGetHeight(labelFrame) / 2

            var newFlipTransform = CATransform3DIdentity
            newFlipTransform = CATransform3DTranslate(newFlipTransform, 0, halfTitleHeight, 0)
            newFlipTransform.m34 = -1.0 / 200.0 // add some perspective
            newFlipTransform = CATransform3DRotate(newFlipTransform, CGFloat(-M_PI_2), 1.0, 0.0, 0.0)
            newTabsButton.titleLabel?.layer.transform = newFlipTransform

            var oldFlipTransform = CATransform3DIdentity
            oldFlipTransform = CATransform3DTranslate(oldFlipTransform, 0, halfTitleHeight, 0)
            oldFlipTransform.m34 = -1.0 / 200.0 // add some perspective
            oldFlipTransform = CATransform3DRotate(oldFlipTransform, CGFloat(M_PI_2), 1.0, 0.0, 0.0)

            UIView.animateWithDuration(1.5, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.0, options: UIViewAnimationOptions.CurveEaseInOut, animations: { _ in
                newTabsButton.titleLabel?.layer.transform = CATransform3DIdentity
                self.tabsButton.titleLabel?.layer.transform = oldFlipTransform
                self.tabsButton.titleLabel?.layer.opacity = 0
                }, completion: { _ in
                    // remove the clone and setup the actual tab button
                    newTabsButton.removeFromSuperview()

                    self.tabsButton.titleLabel?.layer.opacity = 1
                    self.tabsButton.titleLabel?.layer.transform = CATransform3DIdentity
                    self.tabsButton.setTitle(count.description, forState: UIControlState.Normal)
                    self.tabsButton.accessibilityValue = count.description
                    self.tabsButton.accessibilityLabel = NSLocalizedString("Show Tabs", comment: "Accessibility label for the tabs button in the (top) browser toolbar")
            })
        }
    }

    func updateProgressBar(progress: Float) {
        if progress == 1.0 {
            self.progressBar.setProgress(progress, animated: true)
            UIView.animateWithDuration(1.5, animations: {
                self.progressBar.alpha = 0.0
            }, completion: { _ in
                self.progressBar.setProgress(0.0, animated: false)
            })
        } else {
            self.progressBar.alpha = 1.0
            self.progressBar.setProgress(progress, animated: (progress > progressBar.progress))
        }
    }

    func updateReaderModeState(state: ReaderModeState) {
        locationView.readerModeState = state
    }

    func setAutocompleteSuggestion(suggestion: String?) {
        editTextField.setAutocompleteSuggestion(suggestion)
    }

    func finishEditing() {
        editTextField.resignFirstResponder()
        updateLayoutForEditing(editing: false)
        delegate?.urlBarDidEndEditing(self)
    }

    func prepareEditingAnimation(editing: Bool) {
        // Make sure everything is showing during the transition (we'll hide it afterwards).
        self.progressBar.hidden = editing
        self.locationView.hidden = editing
        self.editTextField.hidden = !editing
        self.tabsButton.hidden = false
        self.cancelButton.hidden = false
        self.forwardButton.hidden = !self.toolbarIsShowing
        self.backButton.hidden = !self.toolbarIsShowing
        self.stopReloadButton.hidden = !self.toolbarIsShowing
        self.shareButton.hidden = !self.toolbarIsShowing
        self.bookmarkButton.hidden = !self.toolbarIsShowing

        // Update the location bar's size. If we're animating, we'll call layoutIfNeeded in the Animation
        // and transition to this.
        if editing {
            // In editing mode, we always show the location view full width
            self.locationContainer.snp_remakeConstraints { make in
                make.leading.equalTo(self).offset(URLBarViewUX.LocationLeftPadding)
                make.trailing.equalTo(self.cancelButton.snp_leading)
                make.height.equalTo(URLBarViewUX.LocationHeight)
                make.centerY.equalTo(self)
            }
        } else {
            self.locationContainer.snp_remakeConstraints { make in
                if self.toolbarIsShowing {
                    // If we are showing a toolbar, show the text field next to the forward button
                    make.left.equalTo(self.stopReloadButton.snp_right)
                    make.right.equalTo(self.shareButton.snp_left)
                } else {
                    // Otherwise, left align the location view
                    make.leading.equalTo(self).offset(URLBarViewUX.LocationLeftPadding)
                    make.trailing.equalTo(self.tabsButton.snp_leading).offset(-14)
                }

                make.height.equalTo(URLBarViewUX.LocationHeight)
                make.centerY.equalTo(self)
            }
        }
    }

    func transitionToEditing(editing: Bool) {
        self.cancelButton.alpha = editing ? 1 : 0
        self.shareButton.alpha = editing ? 0 : 1
        self.bookmarkButton.alpha = editing ? 0 : 1

        if editing {
            self.cancelButton.transform = CGAffineTransformIdentity
            let tabsButtonTransform = CGAffineTransformMakeTranslation(self.tabsButton.frame.width + URLBarViewUX.URLBarCurveOffset, 0)
            self.tabsButton.transform = tabsButtonTransform
            self.clonedTabsButton?.transform = tabsButtonTransform
            self.curveShape.transform = CGAffineTransformMakeTranslation(self.tabsButton.frame.width + URLBarViewUX.URLBarCurveOffset + URLBarViewUX.URLBarCurveBounceBuffer, 0)

            if self.toolbarIsShowing {
                self.backButtonLeftConstraint?.updateOffset(-3 * AppConstants.ToolbarHeight)
            }
        } else {
            self.tabsButton.transform = CGAffineTransformIdentity
            self.clonedTabsButton?.transform = CGAffineTransformIdentity
            self.cancelButton.transform = CGAffineTransformMakeTranslation(self.cancelButton.frame.width, 0)
            self.curveShape.transform = CGAffineTransformIdentity

            if self.toolbarIsShowing {
                self.backButtonLeftConstraint?.updateOffset(0)
            }
        }
    }

    func finishEditingAnimation(editing: Bool) {
        self.tabsButton.hidden = editing
        self.cancelButton.hidden = !editing
        self.forwardButton.hidden = !self.toolbarIsShowing || editing
        self.backButton.hidden = !self.toolbarIsShowing || editing
        self.shareButton.hidden = !self.toolbarIsShowing || editing
        self.bookmarkButton.hidden = !self.toolbarIsShowing || editing
        self.stopReloadButton.hidden = !self.toolbarIsShowing || editing
    }

    func updateLayoutForEditing(#editing: Bool, animated: Bool = true) {
        prepareEditingAnimation(editing)

        if animated {
            self.layoutIfNeeded()
            UIView.animateWithDuration(0.3, delay: 0.0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.0, options: nil, animations: { _ in
                self.transitionToEditing(editing)
                self.layoutIfNeeded()
            }, completion: { _ in
                self.finishEditingAnimation(editing)
            })
        } else {
            finishEditingAnimation(editing)
        }
    }

    func SELdidClickAddTab() {
        delegate?.urlBarDidPressTabs(self)
    }

    func SELdidClickCancel() {
        finishEditing()
    }
}

extension URLBarView: BrowserToolbarProtocol {
    func updateBackStatus(canGoBack: Bool) {
        backButton.enabled = canGoBack
    }

    func updateForwardStatus(canGoForward: Bool) {
        forwardButton.enabled = canGoForward
    }

    func updateBookmarkStatus(isBookmarked: Bool) {
        bookmarkButton.selected = isBookmarked
    }

    func updateReloadStatus(isLoading: Bool) {
        if isLoading {
            stopReloadButton.setImage(helper?.ImageStop, forState: .Normal)
            stopReloadButton.setImage(helper?.ImageStopPressed, forState: .Highlighted)
        } else {
            stopReloadButton.setImage(helper?.ImageReload, forState: .Normal)
            stopReloadButton.setImage(helper?.ImageReloadPressed, forState: .Highlighted)
        }
    }

    func updatePageStatus(#isWebPage: Bool) {
        bookmarkButton.enabled = isWebPage
        stopReloadButton.enabled = isWebPage
        shareButton.enabled = isWebPage
    }

    override var accessibilityElements: [AnyObject]! {
        get {
            if isEditing {
                return [editTextField, cancelButton]
            } else {
                if toolbarIsShowing {
                    return [backButton, forwardButton, stopReloadButton, locationView, shareButton, bookmarkButton, tabsButton, progressBar]
                } else {
                    return [locationView, tabsButton, progressBar]
                }
            }
        }
        set {
            super.accessibilityElements = newValue
        }
    }
}

extension URLBarView: BrowserLocationViewDelegate {
    func browserLocationViewDidLongPressReaderMode(browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidLongPressReaderMode(self)
    }

    func browserLocationViewDidTapLocation(browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidBeginEditing(self)

        editTextField.text = locationView.url?.absoluteString
        editTextField.becomeFirstResponder()

        updateLayoutForEditing(editing: true)
    }

    func browserLocationViewDidLongPressLocation(browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidLongPressLocation(self)
    }

    func browserLocationViewDidTapReload(browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidPressReload(self)
    }
    
    func browserLocationViewDidTapStop(browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidPressStop(self)
    }

    func browserLocationViewDidTapReaderMode(browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidPressReaderMode(self)
    }
}

extension URLBarView: AutocompleteTextFieldDelegate {
    func autocompleteTextFieldShouldReturn(autocompleteTextField: AutocompleteTextField) -> Bool {
        delegate?.urlBar(self, didSubmitText: editTextField.text)
        return true
    }

    func autocompleteTextField(autocompleteTextField: AutocompleteTextField, didTextChange text: String) {
        delegate?.urlBar(self, didEnterText: text)
    }

    func autocompleteTextFieldDidBeginEditing(autocompleteTextField: AutocompleteTextField) {
        delegate?.urlBarDidBeginEditing(self)
        autocompleteTextField.highlightAll()
    }

    func autocompleteTextFieldShouldClear(autocompleteTextField: AutocompleteTextField) -> Bool {
        delegate?.urlBar(self, didEnterText: "")
        return true
    }
}

/* Code for drawing the urlbar curve */
// Curve's aspect ratio
private let ASPECT_RATIO = 0.729

// Width multipliers
private let W_M1 = 0.343
private let W_M2 = 0.514
private let W_M3 = 0.49
private let W_M4 = 0.545
private let W_M5 = 0.723

// Height multipliers
private let H_M1 = 0.25
private let H_M2 = 0.5
private let H_M3 = 0.72
private let H_M4 = 0.961

/* Code for drawing the urlbar curve */
private class CurveView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        self.opaque = false
        self.contentMode = .Redraw
    }

    private func getWidthForHeight(height: Double) -> Double {
        return height * ASPECT_RATIO
    }

    private func drawFromTop(path: UIBezierPath) {
        let height: Double = Double(AppConstants.ToolbarHeight)
        let width = getWidthForHeight(height)
        var from = (Double(self.frame.width) - width * 2 - Double(URLBarViewUX.URLBarCurveOffset - URLBarViewUX.URLBarCurveBounceBuffer), Double(0))

        path.moveToPoint(CGPoint(x: from.0, y: from.1))
        path.addCurveToPoint(CGPoint(x: from.0 + width * W_M2, y: from.1 + height * H_M2),
              controlPoint1: CGPoint(x: from.0 + width * W_M1, y: from.1),
              controlPoint2: CGPoint(x: from.0 + width * W_M3, y: from.1 + height * H_M1))

        path.addCurveToPoint(CGPoint(x: from.0 + width,        y: from.1 + height),
              controlPoint1: CGPoint(x: from.0 + width * W_M4, y: from.1 + height * H_M3),
              controlPoint2: CGPoint(x: from.0 + width * W_M5, y: from.1 + height * H_M4))
    }

    private func getPath() -> UIBezierPath {
        let path = UIBezierPath()
        self.drawFromTop(path)
        path.addLineToPoint(CGPoint(x: self.frame.width, y: AppConstants.ToolbarHeight))
        path.addLineToPoint(CGPoint(x: self.frame.width, y: 0))
        path.addLineToPoint(CGPoint(x: 0, y: 0))
        path.closePath()
        return path
    }

    override func drawRect(rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        CGContextSaveGState(context)
        CGContextClearRect(context, rect)
        CGContextSetFillColorWithColor(context, URLBarViewUX.backgroundColorWithAlpha(1).CGColor)
        self.getPath().fill()
        CGContextDrawPath(context, kCGPathFill)
        CGContextRestoreGState(context)
    }
}

private class ToolbarTextField: AutocompleteTextField {
    override func textRectForBounds(bounds: CGRect) -> CGRect {
        let rect = super.textRectForBounds(bounds)
        return rect.rectByInsetting(dx: 5, dy: 5)
    }

    override func editingRectForBounds(bounds: CGRect) -> CGRect {
        let rect = super.editingRectForBounds(bounds)
        return rect.rectByInsetting(dx: 5, dy: 5)
    }
}
