//
//  FeedController.swift
//  FirebaseFeed
//
//  Created by Guido Marucci Blas on 2/4/16.
//  Copyright © 2016 guidomb. All rights reserved.
//

import UIKit
import Firebase
import ReactiveCocoa
import MBProgressHUD

func desarializeMessage(messageSnapshot: FDataSnapshot) -> Message {
    let value = messageSnapshot.value as! [String : AnyObject]
    let messageContent = value["content"] as! String
    let createdBy = value["created_by"] as! String
    let createdAt = value["created_at"] as! Int
    return Message(content: messageContent, createdAt: createdAt, createdBy: createdBy)
}

final class MessageCell: UITableViewCell {
    
    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: .Subtitle, reuseIdentifier: "MessageCell")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func bind(message: Message) {
        detailTextLabel?.text = "by @\(message.createdBy) - \(message.createdAt)"
        textLabel?.text = message.content
    }
    
}

final class FeedController: UITableViewController {
    
    let firebaseClient: Firebase
    let messages = MutableProperty<[Message]>([])
    let user: User
    
    var consumedAllPages = false
    
    init(firebaseClient: Firebase, user: User) {
        self.firebaseClient = firebaseClient
        self.user = user
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var rac_willDeallocProducer: SignalProducer<(), NoError> {
        return rac_willDeallocSignal()
            .toSignalProducer()
            .flatMapError { _ in SignalProducer.empty }
            .map { _ in () }
    }
    
    override func viewDidLoad() {
        tableView.registerClass(MessageCell.self, forCellReuseIdentifier: "MessageCell")
        messages.signal.observeNext { [unowned self] _ in self.tableView.reloadData() }
        
        // Add New Message button
        let newMessageButton = UIBarButtonItem(barButtonSystemItem: .Compose, target: self, action: Selector("newMessage"))
        navigationItem.rightBarButtonItem = newMessageButton
        navigationItem.title = "Messages"

        // Listen for new messages
        messages <~ firebaseClient.childByAppendingPath("feed")
            .observeEventType(.ChildAdded)
            .takeUntil(rac_willDeallocProducer)
            .map(desarializeMessage)
            .map { [unowned self] message -> [Message] in
                var newMessages = [message]
                newMessages.appendContentsOf(self.messages.value)
                return newMessages
            }
            .observeOn(UIScheduler())
        
        // Fetch first page
        messages <~ fetchMessagesNextPage()
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.value.count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("MessageCell", forIndexPath: indexPath) as! MessageCell
        let message = messages.value[indexPath.row]
        cell.bind(message)
        return cell
    }
    
    override func tableView(tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {
        if !consumedAllPages && messages.value.count - indexPath.row <= 3 {
            messages <~ fetchMessagesNextPage().on(started: {
                let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .Gray)
                activityIndicator.startAnimating()
                dispatch_async(dispatch_get_main_queue()) {
                    self.tableView.tableFooterView = activityIndicator
                }
            }, next: { messages in
                self.consumedAllPages = messages.isEmpty
            }, completed: {
                dispatch_async(dispatch_get_main_queue()) {
                    self.tableView.tableFooterView = nil
                }
            })
        }
    }
    
    func fetchMessagesNextPage(amount: UInt = 10) -> SignalProducer<[Message], NoError> {
        var query = firebaseClient.childByAppendingPath("feed")
            .queryOrderedByChild("created_at")
            .queryLimitedToFirst(amount)
        
        if let lastMessage = messages.value.last {
            query = query.queryStartingAtValue(lastMessage.createdAt, childKey: "created_at")
        }
        
        return query.rac_observeSingleEventOfType(.Value)
            .map { messagesSnapshot in
                if messagesSnapshot.value is NSNull {
                    return []
                } else {
                    var messages:[Message] = []
                    for message in messagesSnapshot.children {
                        messages.append(desarializeMessage(message as! FDataSnapshot))
                    }
                    return messages
                }
            }
        
    }
    
    func newMessage() {
        let controller = NewMessageController { messageContent in
            let data: [NSObject: AnyObject] = [
                "content" : messageContent,
                "created_by" : self.user.name,
                "created_at" : FirebaseServerValue.timestamp()
            ]
            
            MBProgressHUD.showHUDAddedTo(self.view, animated: true)
            self.firebaseClient
                .childByAppendingPath("feed")
                .childByAutoId()
                .updateChildValues(data)
                .observeOn(UIScheduler())
                .start {
                    switch $0 {
                    case .Failed(let error):
                        MBProgressHUD.hideAllHUDsForView(self.view, animated: true)
                        print("Error posting new message: \(error)")
                        let alert = UIAlertController(title: "Error posting message", message: error.localizedDescription, preferredStyle: .Alert)
                        let dismissAction = UIAlertAction(title: "OK", style: .Default) { _ in }
                        alert.addAction(dismissAction)
                        self.presentViewController(alert, animated: true, completion: nil)
                    default:
                        MBProgressHUD.hideAllHUDsForView(self.view, animated: true)
                    }
                }
            self.navigationController?.popViewControllerAnimated(true)
        }
        navigationController?.pushViewController(controller, animated: true)
    }
    
}