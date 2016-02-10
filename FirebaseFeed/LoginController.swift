//
//  ViewController.swift
//  FirebaseFeed
//
//  Created by Guido Marucci Blas on 2/3/16.
//  Copyright © 2016 guidomb. All rights reserved.
//

import UIKit
import Neon
import Firebase
import ReactiveCocoa
import Rex
import MBProgressHUD

final class LoginController: UIViewController {

    let emailLabel = UILabel()
    let passwordLabel = UILabel()
    let emailTextField = UITextField()
    let passwordTextField = UITextField()
    let registerButton = UIButton()
    let loginButton = UIButton()
    
    var keyboardDisplayed = false
    
    var onLoggedInEvent: User -> ()
    
    let firebaseClient: Firebase
    
    init(firebaseClient: Firebase, onLoggedInEvent: User -> () = { _ in }) {
        self.onLoggedInEvent = onLoggedInEvent
        self.firebaseClient = firebaseClient
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup view
        
        emailTextField.delegate = self
        passwordTextField.delegate = self
        
        view.backgroundColor = UIColor.whiteColor()
        
        registerButton.backgroundColor = UIColor.redColor()
        registerButton.setTitleColor(UIColor.whiteColor(), forState: .Normal)
        registerButton.setTitle("Register", forState: .Normal)
        
        loginButton.backgroundColor = UIColor.blueColor()
        loginButton.setTitleColor(UIColor.whiteColor(), forState: .Normal)
        loginButton.setTitle("Login", forState: .Normal)
        
        emailLabel.text = "Email"
        emailLabel.textAlignment = .Center
        emailTextField.placeholder = "enter an email address"
        emailTextField.textAlignment = .Center
        
        passwordLabel.text = "Password"
        passwordLabel.textAlignment = .Center
        passwordTextField.secureTextEntry = true
        passwordTextField.placeholder = "enter a password"
        passwordTextField.textAlignment = .Center
        
        
        // Setup layout
        
        view.addSubview(emailLabel)
        view.addSubview(passwordLabel)
        view.addSubview(emailTextField)
        view.addSubview(passwordTextField)
        view.addSubview(registerButton)
        view.addSubview(loginButton)
        
        registerButton.anchorAndFillEdge(.Bottom, xPad: 0, yPad: 0, otherSize: view.height * 0.10)
        loginButton.alignAndFillWidth(align: .AboveCentered, relativeTo: registerButton, padding: 0, height: view.height * 0.10)
        
        passwordTextField.alignAndFillWidth(align: .AboveCentered, relativeTo: loginButton, padding: 100, height: 50)
        passwordLabel.alignAndFillWidth(align: .AboveCentered, relativeTo: passwordTextField, padding: 10, height: 50)
        emailTextField.alignAndFillWidth(align: .AboveCentered, relativeTo: passwordLabel, padding: 30, height: 50)
        emailLabel.alignAndFillWidth(align: .AboveCentered, relativeTo: emailTextField, padding: 10, height: 50)
        
        // Setup actions
        let validCredentialsProducer = emailTextField.rex_textSignal
            .combineLatestWith(passwordTextField.rex_textSignal)
            .map { email, password in !email.isEmpty && !password.isEmpty && email.isValidEmail() }
        let creadentialsAreValid = AnyProperty<Bool>(initialValue: false, producer: validCredentialsProducer)
        
        let loginProducer = { (email: String, password: String) in
            self.firebaseClient.authUser(email, password: password).map { ($0.uid as String, $0.token as String) }
        }
        
        let loginAction = Action<AnyObject, (String, String), NSError>(enabledIf: creadentialsAreValid) { _  in
            let email = self.emailTextField.text!
            let password = self.passwordTextField.text!
            return loginProducer(email, password)
        }
        
        let registerAction = Action<AnyObject, (String, String), NSError>(enabledIf: creadentialsAreValid) { _  in
            let email = self.emailTextField.text!
            let password = self.passwordTextField.text!
            return self.firebaseClient.createUser(email, password: password)
                .flatMap(.Concat) { _ in loginProducer(email, password) }
        }
        
        // Bind actions
        loginButton.rex_pressed.value = loginAction.unsafeCocoaAction
        registerButton.rex_pressed.value = registerAction.unsafeCocoaAction
        
        let scheduler = UIScheduler()
        SignalProducer(values: [loginAction.executing.producer, registerAction.executing.producer])
            .flatten(.Merge)
            .observeOn(scheduler)
            .startWithNext { executing in
                if executing {
                    MBProgressHUD.showHUDAddedTo(self.view, animated: true)
                } else {
                    MBProgressHUD.hideAllHUDsForView(self.view, animated: true)
                }
            }
        
        SignalProducer(values: [loginAction.errors, registerAction.errors])
            .flatten(.Merge)
            .observeOn(scheduler)
            .startWithNext { error in
                let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .Alert)
                let dismissAction = UIAlertAction(title: "OK", style: .Default) { _ in }
                alert.addAction(dismissAction)
                
                self.presentViewController(alert, animated: true, completion: nil)
            }
        
        registerAction.values.observeOn(scheduler).observeNext { uid, token in
            let alert = UIAlertController(title: "Username", message: "Enter your username", preferredStyle: .Alert)
            let saveAction = UIAlertAction(title: "OK", style: .Default) { _ in
                MBProgressHUD.showHUDAddedTo(self.view, animated: true)
                // TODO handler error
                let username = alert.textFields?.first?.text ?? ""
                let userProperties = [ "username" : username ]
                self.firebaseClient.childByAppendingPath("users")
                    .setValue([uid:userProperties])
                    .observeOn(scheduler)
                    .startWithNext { _ in
                        let userDefaults = NSUserDefaults.standardUserDefaults()
                        userDefaults.setObject(NSString(UTF8String: token), forKey: "auth-token")
                        userDefaults.synchronize()
                        
                        MBProgressHUD.hideAllHUDsForView(self.view, animated: true)
                        alert.dismissViewControllerAnimated(true, completion: nil)
                        self.onLoggedInEvent(User(uid: uid, name: username))
                    }
            }
            alert.addAction(saveAction)
            alert.addTextFieldWithConfigurationHandler { textField in
                textField.placeholder = "username"
                textField.rex_textSignal.startWithNext { saveAction.enabled = !$0.isEmpty }
            }
            saveAction.enabled = false
            
            self.presentViewController(alert, animated: true, completion: nil)
        }
        
        loginAction.values.observeNext { uid, token in
            self.firebaseClient.childByAppendingPath("users/\(uid)")
                .observeSingleEventOfType(.Value)
                .observeOn(scheduler)
                .startWithNext { snapshot in
                    let userDefaults = NSUserDefaults.standardUserDefaults()
                    userDefaults.setObject(NSString(UTF8String: token), forKey: "auth-token")
                    userDefaults.synchronize()
                    
                    let data = snapshot.value as! NSDictionary
                    let username = data["username"] as! String
                    self.onLoggedInEvent(User(uid: uid, name: username))
                }
        }

        // Login user if credentials are available
        let userDefaults = NSUserDefaults.standardUserDefaults()
        if let token = userDefaults.objectForKey("auth-token") as? String {
            print("Logging in user using stored credentials")
            MBProgressHUD.showHUDAddedTo(self.view, animated: true)
            firebaseClient.authWithCustomToken(token)
                .flatMap(FlattenStrategy.Concat) { (authData: FAuthData) -> SignalProducer<User, NSError> in
                    return self.firebaseClient.childByAppendingPath("users/\(authData.uid)")
                        .observeSingleEventOfType(.Value)
                        .flatMapError { _ in SignalProducer.empty }
                        .map { snapshot in
                            let data = snapshot.value as! NSDictionary
                            let username = data["username"] as! String
                            return User(uid: authData.uid, name: username)
                        }
                }
                .observeOn(UIScheduler())
                .startWithNext { user in
                    MBProgressHUD.hideAllHUDsForView(self.view, animated: true)
                    self.onLoggedInEvent(user)
                }
        }
    }
    
    override func viewWillAppear(animated: Bool) {
        addKeyboardObservers()
    }
    
    override func viewWillDisappear(animated: Bool) {
        removeKeyboardObservers()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

extension LoginController {
    
    func addKeyboardObservers() {
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("keyboardDidHide:"), name: UIKeyboardDidHideNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("keyboardWillShow:"), name: UIKeyboardWillShowNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("keyboardWillHide:"), name: UIKeyboardWillHideNotification, object: nil)
    }
    
    func removeKeyboardObservers() {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIKeyboardDidHideNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIKeyboardWillShowNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIKeyboardWillHideNotification, object: nil)
    }
    
    func keyboardWillShow(notification: NSNotification) {
        if let keyboardSize = (notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.CGRectValue() {
            if !keyboardDisplayed {
                self.view.frame.origin.y -= keyboardSize.height
                keyboardDisplayed = true
            }
        }
    }
    
    func keyboardWillHide(notification: NSNotification) {
        self.view.frame.origin.y = 0
    }
    
    func keyboardDidHide(notification: NSNotification) {
        keyboardDisplayed = false
    }

}


extension LoginController: UITextFieldDelegate {
    
    func textFieldShouldReturn(textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        self.view.endEditing(true)
    }
}
