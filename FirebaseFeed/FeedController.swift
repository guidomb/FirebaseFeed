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
    let userData = messageSnapshot.childSnapshotForPath("created_by").value as! [String : AnyObject]
    let createdBy = userData["username"] as! String
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
    var fetchingNextPage = false
    
    let pageFetcherScheduler = QueueScheduler(queue: dispatch_queue_create("me.guidomb.FirebaseFeed", nil))
    
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
        messages.signal.observeOn(UIScheduler()).observeNext { [unowned self] _ in self.tableView.reloadData() }
        
        // Add New Message button
        let newMessageButton = UIBarButtonItem(barButtonSystemItem: .Compose, target: self, action: Selector("newMessage"))
        navigationItem.rightBarButtonItem = newMessageButton
        navigationItem.title = "Messages"

        
        // Fetch first page
        messages <~ fetchFirstPage()
            .on(completed: listenForNewMessage)
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
        if !fetchingNextPage && !consumedAllPages && messages.value.count - indexPath.row <= 5 {
            
            SignalProducer<[Message], NoError> { observable, disposable in
                if !self.fetchingNextPage && !self.consumedAllPages {
                    self.fetchingNextPage = true
                    observable.sendNext([])
                } else {
                    print("Stopped fetching page because a page is already been fetched")
                }
                observable.sendCompleted()
            }
            .startOn(pageFetcherScheduler) // This will assure that pages are fetched sequentially
            .flatMap(FlattenStrategy.Concat) { _ -> SignalProducer<[Message], NoError> in
                let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .Gray)
                activityIndicator.startAnimating()
                dispatch_async(dispatch_get_main_queue()) {
                    self.tableView.tableFooterView = activityIndicator
                }
                
                print("Fetching next page")
                return self.fetchMessagesNextPage()
            }
            .start { (event: Event<[Message], NoError>) in
                switch event {
                case .Next(let messages):
                    self.consumedAllPages = messages.isEmpty
                    if self.consumedAllPages {
                        print("We have reached the end of the feed")
                    } else {
                        var newMessages = self.messages.value
                        newMessages.appendContentsOf(messages)
                        self.messages.value = newMessages
                    }
                case .Completed:
                    self.fetchingNextPage = false
                    dispatch_async(dispatch_get_main_queue()) {
                        if self.consumedAllPages {
                            let frame = CGRect(x: 0, y: 0, width: self.tableView.width, height: 50)
                            let footer = UILabel(frame: frame)
                            footer.text = "There are no more messages"
                            footer.textAlignment = .Center
                            self.tableView.tableFooterView = footer
                        } else {
                            self.tableView.tableFooterView = nil
                        }
                    }
                default: break
                }
            }
        }
    }
    
    func fetchFirstPage(amount: UInt = 20) -> SignalProducer<[Message], NoError> {
        return firebaseClient.childByAppendingPath("feed")
            .queryOrderedByChild("created_at")
            .queryLimitedToLast(amount)
            .rac_observeSingleEventOfType(.Value)
            .map { messagesSnapshot in
                if messagesSnapshot.value is NSNull {
                    return []
                } else {
                    var messages:[Message] = []
                    for message in messagesSnapshot.children {
                        messages.append(desarializeMessage(message as! FDataSnapshot))
                    }
                    // Ordered query always returns in ascending order
                    messages = messages.reverse()
                    print("Messags in first page: \(messages)")
                    return messages
                }
        }
    }
    
    func listenForNewMessage() {
        let ref = firebaseClient.childByAppendingPath("feed")
        let messageSnapshotProducer: SignalProducer<FDataSnapshot, NoError>
        if messages.value.isEmpty {
            messageSnapshotProducer = ref.observeEventType(.ChildAdded)
        } else {
            messageSnapshotProducer = ref.queryLimitedToLast(1)
                .rac_observeEventType(.ChildAdded)
                .skip(1)
        }
        messages <~ messageSnapshotProducer
            .takeUntil(rac_willDeallocProducer)
            .map(desarializeMessage)
            .map { [unowned self] message -> [Message] in
                print("New message available: \(message)")
                var newMessages = [message]
                newMessages.appendContentsOf(self.messages.value)
                return newMessages
            }
            .observeOn(UIScheduler())
    }
    
    func fetchMessagesNextPage(amount: UInt = 10) -> SignalProducer<[Message], NoError> {
        var query = firebaseClient.childByAppendingPath("feed")
            .queryOrderedByChild("created_at")
            .queryLimitedToLast(amount)
        
        if let lastMessage = messages.value.last {
            query = query.queryEndingAtValue(lastMessage.createdAt, childKey: "created_at")
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
                    // Ordered query always returns in ascending order
                    messages = messages.reverse()
                    // We remove the first because it is the oldest element in the previous
                    // page. queryEndingAtValue includes that element in the result
                    messages.removeFirst()
                    print("Messages in fetched page: \(messages)")
                    return messages
                }
            }
        
    }
    
    func newMessage() {
        let controller = NewMessageController { messageContent in
            let userData: [NSObject : AnyObject] = [
                "username" : self.user.name,
                "uid" : self.user.uid
            ]
            let messageData: [NSObject: AnyObject] = [
                "content" : messageContent,
                "created_by" : userData,
                "created_at" : FirebaseServerValue.timestamp()
            ]
            
            MBProgressHUD.showHUDAddedTo(self.view, animated: true)
            self.firebaseClient
                .childByAppendingPath("feed")
                .childByAutoId()
                .updateChildValues(messageData)
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