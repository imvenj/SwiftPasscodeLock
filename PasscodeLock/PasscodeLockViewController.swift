//
//  PasscodeLockViewController.swift
//  PasscodeLock
//
//  Created by Yanko Dimitrov on 8/28/15.
//  Copyright © 2015 Yanko Dimitrov. All rights reserved.
//

import UIKit

open class PasscodeLockViewController: UIViewController, PasscodeLockTypeDelegate {
    
    public enum LockState {
        case enterPasscode
        case setPasscode
        case changePasscode
        case removePasscode
        
        func getState() -> PasscodeLockStateType {
            
            switch self {
            case .enterPasscode: return EnterPasscodeState()
            case .setPasscode: return SetPasscodeState()
            case .changePasscode: return ChangePasscodeState()
            case .removePasscode: return EnterPasscodeState(allowCancellation: true)
            }
        }
    }

    @IBOutlet open var numberKeys: [PasscodeSignButton] = []
    @IBOutlet open weak var titleLabel: UILabel?
    @IBOutlet open weak var descriptionLabel: UILabel?
    @IBOutlet open var placeholders: [PasscodeSignPlaceholderView] = [PasscodeSignPlaceholderView]()
    @IBOutlet open weak var cancelButton: UIButton?
    @IBOutlet open weak var deleteSignButton: UIButton?
    @IBOutlet open weak var biometricAuthButton: UIButton!
    @IBOutlet open weak var placeholdersX: NSLayoutConstraint?
    
    open var successCallback: ((_ lock: PasscodeLockType) -> Void)?
    open var dismissCompletionCallback: (()->Void)?
    open var animateOnDismiss: Bool
    open var notificationCenter: NotificationCenter?
    open var mainColor: UIColor = UIColor(red: 117.0 / 255.0, green: 154.0 / 255.0, blue: 228.0 / 255.0, alpha: 0) {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let `self` = self else { return }
                self.numberKeys.forEach {
                    $0.borderColor = self.mainColor
                    $0.setTitleColor(self.mainColor, for: .normal)
                    $0.highlightBackgroundColor = self.mainColor
                }
                self.placeholders.forEach {
                    $0.activeColor = self.mainColor
                    if #available(iOS 13.0, *) {
                        #if os(iOS)
                        $0.inactiveColor = .systemBackground
                        #else
                        $0.inactiveColor = .white
                        #endif
                    } else {
                        $0.inactiveColor = .white
                    }
                    $0.errorColor = UIColor(red: 243.0 / 255.0, green: 123.0 / 255.0, blue: 123.0 / 255.0, alpha: 0)
                }
                self.cancelButton?.setTitleColor(self.mainColor, for: .normal)
                self.cancelButton?.setTitleColor(self.mainColor.withAlphaComponent(0.5), for: .disabled)
                self.deleteSignButton?.setTitleColor(self.mainColor, for: .normal)
                self.deleteSignButton?.setTitleColor(self.mainColor.withAlphaComponent(0.5), for: .disabled)
                self.biometricAuthButton?.setTitleColor(self.mainColor, for: .normal)
                self.biometricAuthButton?.setTitleColor(self.mainColor.withAlphaComponent(0.5), for: .disabled)
            }
        }
    }

    internal let passcodeConfiguration: PasscodeLockConfigurationType
    internal var passcodeLock: PasscodeLockType
    internal var isPlaceholdersAnimationCompleted = true
    
    fileprivate var shouldTryToAuthenticateWithBiometrics = true
    
    // MARK: - Initializers
    
    public init(state: PasscodeLockStateType, configuration: PasscodeLockConfigurationType, animateOnDismiss: Bool = true, nibName: String = "PasscodeLockView", bundle: Bundle? = nil) {
        
        self.animateOnDismiss = animateOnDismiss
        
        passcodeConfiguration = configuration
        passcodeLock = PasscodeLock(state: state, configuration: configuration)
        
        let bundleToUse = bundle ?? bundleForResource(nibName, ofType: "nib")
        
        super.init(nibName: nibName, bundle: bundleToUse)
        
        passcodeLock.delegate = self
        notificationCenter = NotificationCenter.default
    }
    
    public convenience init(state: LockState, configuration: PasscodeLockConfigurationType, animateOnDismiss: Bool = true) {
        
        self.init(state: state.getState(), configuration: configuration, animateOnDismiss: animateOnDismiss)
    }
    
    public required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        
        clearEvents()
    }
    
    // MARK: - View
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        deleteSignButton?.isEnabled = false
        
        setupEvents()
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        updatePasscodeView()
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if shouldTryToAuthenticateWithBiometrics && passcodeConfiguration.shouldRequestBiometricAuthImmediately {
        
            authenticateWithBiometrics()
        }
    }
    
    internal func updatePasscodeView() {
        
        titleLabel?.text = passcodeLock.state.title
        descriptionLabel?.text = passcodeLock.state.description
        cancelButton?.isHidden = !passcodeLock.state.isCancellableAction
        biometricAuthButton?.isHidden = !passcodeLock.isBiometricAuthAllowed
    }

    #if os(iOS)
    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UI_USER_INTERFACE_IDIOM() == .phone {
            return [.portrait, .portraitUpsideDown]
        }
        else {
            return .all
        }
    }
    #endif
    
    // MARK: - Events
    
    fileprivate func setupEvents() {
        
        notificationCenter?.addObserver(self, selector: #selector(PasscodeLockViewController.appWillEnterForegroundHandler(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        notificationCenter?.addObserver(self, selector: #selector(PasscodeLockViewController.appDidEnterBackgroundHandler(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    fileprivate func clearEvents() {
        
        notificationCenter?.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        notificationCenter?.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    @objc open func appWillEnterForegroundHandler(_ notification: Notification) {
        
        if passcodeConfiguration.shouldRequestBiometricAuthImmediately {
            authenticateWithBiometrics()
        }
    }
    
    @objc open func appDidEnterBackgroundHandler(_ notification: Notification) {
        
        shouldTryToAuthenticateWithBiometrics = false
    }
    
    // MARK: - Actions
    
    @IBAction func passcodeSignButtonTap(_ sender: PasscodeSignButton) {
        
        guard isPlaceholdersAnimationCompleted else { return }
        
        passcodeLock.addSign(sender.passcodeSign)
    }
    
    @IBAction func cancelButtonTap(_ sender: UIButton) {
        
        dismissPasscodeLock(passcodeLock)
    }
    
    @IBAction func deleteSignButtonTap(_ sender: UIButton) {
        
        passcodeLock.removeSign()
    }
    
    @IBAction func biometricAuthButtonTap(_ sender: UIButton) {
        
        passcodeLock.authenticateWithBiometrics()
    }
    
    open func authenticateWithBiometrics() {
        
        guard passcodeConfiguration.repository.hasPasscode else { return }

        if passcodeLock.isBiometricAuthAllowed {
            
            passcodeLock.authenticateWithBiometrics()
        }
    }
    
    internal func dismissPasscodeLock(_ lock: PasscodeLockType, completionHandler: (() -> Void)? = nil) {
        
        // if presented as modal
        if presentingViewController?.presentedViewController == self {
            
            dismiss(animated: animateOnDismiss, completion: { [weak self] in
                
                self?.dismissCompletionCallback?()
                
                completionHandler?()
            })
            
            return
            
        // if pushed in a navigation controller
        } else if navigationController != nil {

            navigationController?.popViewController(animated: animateOnDismiss)
        }
        
        dismissCompletionCallback?()
        
        completionHandler?()
    }
    
    // MARK: - Animations
    
    internal func animateWrongPassword() {
        
        deleteSignButton?.isEnabled = false
        isPlaceholdersAnimationCompleted = false
        
        animatePlaceholders(placeholders, toState: .error)
        
        placeholdersX?.constant = -40
        view.layoutIfNeeded()
        
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.2,
            initialSpringVelocity: 0,
            options: [],
            animations: {
                
                self.placeholdersX?.constant = 0
                self.view.layoutIfNeeded()
            },
            completion: { completed in
                
                self.isPlaceholdersAnimationCompleted = true
                self.animatePlaceholders(self.placeholders, toState: .inactive)
        })
    }
    
    internal func animatePlaceholders(_ placeholders: [PasscodeSignPlaceholderView], toState state: PasscodeSignPlaceholderView.State) {
        
        for placeholder in placeholders {
            
            placeholder.animateState(state)
        }
    }
    
    fileprivate func animatePlacehodlerAtIndex(_ index: Int, toState state: PasscodeSignPlaceholderView.State) {
        
        guard index < placeholders.count && index >= 0 else { return }
        
        placeholders[index].animateState(state)
    }

    // MARK: - PasscodeLockDelegate
    
    open func passcodeLockDidSucceed(_ lock: PasscodeLockType) {
        
        deleteSignButton?.isEnabled = true
        animatePlaceholders(placeholders, toState: .inactive)
        dismissPasscodeLock(lock, completionHandler: { [weak self] in
            self?.successCallback?(lock)
        })
    }
    
    open func passcodeLockDidFail(_ lock: PasscodeLockType) {
        
        animateWrongPassword()
    }
    
    open func passcodeLockDidChangeState(_ lock: PasscodeLockType) {
        
        updatePasscodeView()
        animatePlaceholders(placeholders, toState: .inactive)
        deleteSignButton?.isEnabled = false
    }
    
    open func passcodeLock(_ lock: PasscodeLockType, addedSignAtIndex index: Int) {
        
        animatePlacehodlerAtIndex(index, toState: .active)
        deleteSignButton?.isEnabled = true
    }
    
    open func passcodeLock(_ lock: PasscodeLockType, removedSignAtIndex index: Int) {
        
        animatePlacehodlerAtIndex(index, toState: .inactive)
        
        if index == 0 {
            
            deleteSignButton?.isEnabled = false
        }
    }
}
