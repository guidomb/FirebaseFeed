//
//  UITextFieldExtensions.swift
//  FirebaseFeed
//
//  Created by Guido Marucci Blas on 2/4/16.
//  Copyright © 2016 guidomb. All rights reserved.
//

import UIKit
import ReactiveCocoa

extension UITextField {
    
    /// Sends the field's string value whenever it changes.
    public var rex_textSignal: SignalProducer<String, NoError> {
        return NSNotificationCenter.defaultCenter()
            .rac_notifications(UITextFieldTextDidChangeNotification, object: self)
            .filterMap { notification in
                guard let textField = notification.object as? UITextField else { return nil}
                return textField.text
        }
    }
}