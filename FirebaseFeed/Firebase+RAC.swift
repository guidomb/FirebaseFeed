//
//  Firebase+RAC.swift
//  FirebaseFeed
//
//  Created by Guido Marucci Blas on 2/3/16.
//  Copyright © 2016 guidomb. All rights reserved.
//

import Foundation
import Firebase
import ReactiveCocoa

typealias FNewUserData = [NSObject : AnyObject]

extension Firebase {
    
    func authUser(email: String, password: String) -> SignalProducer<FAuthData, NSError> {
        return SignalProducer { observable, disposable in
            self.authUser(email, password: password) { error, authData in
                if error == nil {
                    observable.sendNext(authData)
                    observable.sendCompleted()
                } else {
                    observable.sendFailed(error)
                }
            }
        }
    }
    
    func createUser(email: String, password: String) -> SignalProducer<FNewUserData, NSError> {
        return SignalProducer { observable, disposable in
            self.createUser(email, password: password, withValueCompletionBlock: { error, value in
                if error == nil {
                    observable.sendNext(value)
                    observable.sendCompleted()
                } else {
                    observable.sendFailed(error)
                }
            })
        }
    }

    
    func setValue(value: AnyObject) -> SignalProducer<Firebase, NSError> {
        return SignalProducer { observable, disposable in
            self.setValue(value, withCompletionBlock: { (error, ref) -> Void in
                if error == nil {
                    observable.sendNext(ref)
                    observable.sendCompleted()
                } else {
                    observable.sendFailed(error)
                }
            })
        }
    }
    
    func observeSingleEventOfType(type: FEventType) -> SignalProducer<FDataSnapshot, NSError> {
        return SignalProducer { observable, disposable in
            self.observeSingleEventOfType(type, withBlock: { (snapshot) -> Void in
                observable.sendNext(snapshot)
                observable.sendCompleted()
            })
        }
    }
    
}