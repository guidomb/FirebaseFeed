//
//  NewMessageController.swift
//  FirebaseFeed
//
//  Created by Guido Marucci Blas on 2/6/16.
//  Copyright © 2016 guidomb. All rights reserved.
//

import UIKit
import Neon

final class NewMessageController: UIViewController {
    
    let messageTextView = UITextView()
    let onNewMessage: String -> ()
    
    
    init(onNewMessage: String -> ()) {
        self.onNewMessage = onNewMessage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        let doneButton = UIBarButtonItem(barButtonSystemItem: .Done, target: self, action: "done")
        navigationItem.rightBarButtonItem = doneButton
        navigationItem.title = "New message"
        
        view.addSubview(messageTextView)
        messageTextView.anchorAndFillEdge(.Top, xPad: 0, yPad: 0, otherSize: view.height)
    }
    
    func done() {
        onNewMessage(messageTextView.text)
    }
    
}
