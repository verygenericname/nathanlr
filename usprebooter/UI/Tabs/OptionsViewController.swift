//
//  a.swift
//  barracuta
//
//  Created by samara on 1/14/24.
//  Copyright © 2024 samiiau. All rights reserved.
//

import Foundation
import UIKit

class OptionsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate {
    func removeJailbreak() {
        let alertController = UIAlertController(
            title: "Remove Jailbreak",
            message: "Are you sure you want to remove the jailbreak?",
            preferredStyle: .alert
        )
        
        let confirmAction = UIAlertAction(title: "Yes", style: .destructive) { _ in
            let bundlePath = Bundle.main.bundlePath
            let binaryPath = (bundlePath as NSString).appendingPathComponent("NathanLR")
            let args = ["--debootstrap"]
            
            spawnRoot(binaryPath, args, nil, nil, nil)
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
            exit(0)
        }
        
        let cancelAction = UIAlertAction(title: "No", style: .cancel, handler: nil)
        
        alertController.addAction(confirmAction)
        alertController.addAction(cancelAction)
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            if let topController = scene.windows.first?.rootViewController {
                topController.present(alertController, animated: true, completion: nil)
            }
        }
    }
    
    func hideUnhideJB() {
        let bundlePath = Bundle.main.bundlePath
        let binaryPath = (bundlePath as NSString).appendingPathComponent("NathanLR")
        let args = ["--hideJB"]
        
        spawnRoot(binaryPath, args, nil, nil, nil)
        
        let alertController = UIAlertController(
            title: "Respring?",
            message: "Would you like to respring?\nWeird issues might happen if you don't.",
            preferredStyle: .alert
        )
        
        let confirmAction = UIAlertAction(title: "Yes", style: .default) { _ in
            respring()
            exit(0)
        }
        
        let cancelAction = UIAlertAction(title: "No", style: .cancel, handler: nil)
        
        alertController.addAction(confirmAction)
        alertController.addAction(cancelAction)
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            if let topController = scene.windows.first?.rootViewController {
                topController.present(alertController, animated: true, completion: nil)
            }
        }
    }
    
    var tableView: UITableView!
    var tableData = [
        ["About/Credits", "Reboot Userspace"]
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        self.title = "Options/Credits"
        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 40, right: 0)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        if let executablePath = executablePathForPID(1) as String?, executablePath != "/sbin/launchd" {
            tableData[0].append(contentsOf: ["Reboot", "Respring", "Enter Safe Mode", "UICache"])
        }
        
        if let executablePath = executablePathForPID(1) as String?, executablePath == "/sbin/launchd" {
            if FileManager.default.fileExists(atPath: "/var/jb/.procursus_strapped") {
                tableData[0].append(contentsOf: ["Remove Jailbreak"])
            }
        } else {
            tableData[0].append(contentsOf: ["Toggle Jailbreak Hide State"])
        }
        
        if FileManager.default.fileExists(atPath: "/var/jb/.procursus_strapped") {
            if FileManager.default.fileExists(atPath: "/var/jb/basebins/appstorehelper.dylib") {
                tableData[0].append(contentsOf: ["App Injection"])
            }
            if let executablePath = executablePathForPID(1) as String?, executablePath == "/sbin/launchd" {
                tableData[0].append(contentsOf: ["Toggle Safe Mode"])
            }
            
        }
        
        tableView.reloadData()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tableData[section].count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseIdentifier = "Cell"
        let cell = UITableViewCell(style: .value1, reuseIdentifier: reuseIdentifier)
        cell.selectionStyle = .none
        cell.accessoryType = .none
        
        let cellText = tableData[indexPath.section][indexPath.row]
        cell.textLabel?.text = cellText
        cell.accessoryType = .none
        cell.selectionStyle = .default
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cellText = tableData[indexPath.section][indexPath.row]

        switch cellText {
        case "About/Credits":
            let aboutView = AboutViewController()
            let navController = UINavigationController(rootViewController: aboutView)
            self.present(navController, animated: true, completion: nil)
        case "Respring":
            respring()
            exit(0)
        case "App Injection":
            let APView = TDRootViewController()
            let navController = UINavigationController(rootViewController: APView)
            self.present(navController, animated: true, completion: nil)
        case "Reboot Userspace":
            let alert = UIAlertController(
                title: "Reboot Userspace?",
                message: "Are you sure you want to reboot userspace?",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: { _ in
                let ret = reboot3(0x2000000000000000)
                if ret != 0 {
                    userspaceReboot()
                }
            }))
            present(alert, animated: true)
        case "Reboot":
            let alert = UIAlertController(
                title: "Reboot?",
                message: "Are you sure you want to reboot?",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: { _ in
                reboot3(0x8000000000000000)
            }))
            present(alert, animated: true)
        case "UICache":
            let binaryPath = "/var/jb/usr/bin/uicache"
            let args = ["-a"]
            spawnRoot(binaryPath, args, nil, nil, nil)
        case "Toggle Jailbreak Hide State":
            hideUnhideJB()
        case "Enter Safe Mode":
            crashSpringBoard()
            exit(0)
        case "Toggle Safe Mode":
            let path = "/var/mobile/.eksafemode"
            let fm = FileManager.default
            var message = ""

            if fm.fileExists(atPath: path) {
                try? fm.removeItem(atPath: path)
                message = "Safe Mode Disabled"
            } else {
                fm.createFile(atPath: path, contents: nil)
                message = "Safe Mode Enabled"
            }

            let alert = UIAlertController(title: "Safe Mode", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        case "Remove Jailbreak":
            removeJailbreak()
    //    case "Changelogs":
    //        let cView = ChangelogViewController()
    //        navigationController?.pushViewController(cView, animated: true)
        default:
            break
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
}
