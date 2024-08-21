//
//  JailbreakViewController.swift
//  barracuta
//
//  Created by samara on 1/14/24.
//  Copyright © 2024 samiiau. All rights reserved.
//

import UIKit

func fileExists(atPath path: String) -> Bool {
    return FileManager.default.fileExists(atPath: path)
}

class JailbreakViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, LoggerDelegate {

    let tableView = UITableView()
    let cellReuseIdentifier = "Cell"

    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)

        let toolbar = UIToolbar(frame: CGRect(origin: .zero, size: CGSize(width: 100, height: 44.0)))
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        let toolbarHeight: CGFloat = 70
        
        func isCurrentiOSVersionInRange() -> Bool {
            let startVersion = "16.5.1"
            let endVersion = "16.6.1"
            let systemVersion = UIDevice.current.systemVersion
            func versionTuple(from versionString: String) -> (Int, Int, Int) {
                let components = versionString.split(separator: ".").compactMap { Int($0) }
                return (components[0], components[1], components.count > 2 ? components[2] : 0)
            }
            
            let currentVersionTuple = versionTuple(from: systemVersion)
            let startVersionTuple = versionTuple(from: startVersion)
            let endVersionTuple = versionTuple(from: endVersion)
            
            return (currentVersionTuple >= startVersionTuple) && (currentVersionTuple <= endVersionTuple)
        }
        
        if !isCurrentiOSVersionInRange() {
            let jbButton = jbButton(state: .unsupported)
            jbButton.delegate = self
            
            let fileListHeaderItem = UIBarButtonItem(customView: jbButton)

            toolbar.setItems([fileListHeaderItem], animated: false)
        } else if !FileManager.default.fileExists(atPath: "/var/jb/.procursus_strapped") {
            let jbButton = jbButton(state: .bootstrap)
            jbButton.delegate = self
            
            let fileListHeaderItem = UIBarButtonItem(customView: jbButton)

            toolbar.setItems([fileListHeaderItem], animated: false)
        } else if let executablePath = executablePathForPID(1) as String?, executablePath != "/sbin/launchd" {
            let jbButton = jbButton(state: .jailbroken)
            jbButton.delegate = self
            
            let fileListHeaderItem = UIBarButtonItem(customView: jbButton)

            toolbar.setItems([fileListHeaderItem], animated: false)
        } else {
            let jbButton = jbButton(state: .jailbreak)
            jbButton.delegate = self
            
            let fileListHeaderItem = UIBarButtonItem(customView: jbButton)

            toolbar.setItems([fileListHeaderItem], animated: false)
        }
        
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: toolbarHeight),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 80, right: 0)
        
        Logger.shared.delegate = self

        tableView.separatorStyle = .none
        tableView.register(CustomTableViewCell.self, forCellReuseIdentifier: "Cell")
        Logger.shared.log(logType: .name, subTitle: "Supported Versions: 16.5.1 - 16.6.1")
        tableView.reloadData()
    }
    
    func didAddNewLog() {
        DispatchQueue.main.async {
            UIView.transition(with: self.tableView,
                              duration: 0.3,
                              options: .transitionCrossDissolve,
                              animations: {
                self.tableView.reloadData()
                let indexPath = IndexPath(row: Logger.shared.data.count - 1, section: 0)
                self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
            }, completion: nil)
        }
    }


    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Logger.shared.data.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as! CustomTableViewCell
        cell.configure(with: Logger.shared.data[indexPath.row])
        return cell
    }
}

func callSwitchSysBin(vnode: UInt64, what: String, with: String) -> UInt64 {
    var result: UInt64 = 0
    what.withCString { whatCString in
        with.withCString { withCString in
            result = SwitchSysBin(vnode, UnsafeMutablePointer(mutating: whatCString), UnsafeMutablePointer(mutating: withCString))
        }
    }

    return result
}

extension JailbreakViewController: JBButtonDelegate {
    func jbButtonDidFinishAction(_ button: jbButton) {
        button.updateButtonState(.jailbreaking)
        DispatchQueue.global().async {
            krw_init_landa()
            if fileExists(atPath: "/var/jb/sbin/launchd") {
                _ = callSwitchSysBin(vnode: get_vnode_for_path_by_chdir("/sbin"), what: "launchd", with: "/var/jb/sbin/launchd")
            } else if fileExists(atPath: "/var/jb/System/Library/SysBins/launchd") {
                _ = callSwitchSysBin(vnode: get_vnode_for_path_by_chdir("/sbin"), what: "launchd", with: "/var/jb/System/Library/SysBins/launchd")
            }
            krw_deinit()
            userspaceReboot()
        }
    }
    
    func BButtonDidFinishAction(_ button: jbButton) {
        button.updateButtonState(.bootstrapping)
        DispatchQueue.global().async {
            let bundlePath = Bundle.main.bundlePath
            let binaryPath = (bundlePath as NSString).appendingPathComponent("nathanlr")
            let args = ["--bootstrap"]
            
            spawnRoot(binaryPath, args, nil, nil)
            button.updateButtonState(.jailbreak)
        }
    }
}
