//
//  AboutViewController.swift
//  barracuta
//
//  Created by samara on 1/14/24.
//  Copyright © 2024 samiiau. All rights reserved.
//

import Foundation
import UIKit

class AboutViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    var tableData = [[String]]()
    
    
    let sectionTitles = ["Credits", "Acknowledgements"]
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        self.title = "About"
        
        view.addSubview(tableView)
        view.addConstraints([
            NSLayoutConstraint(item: tableView, attribute: .width, relatedBy: .equal, toItem: view, attribute: .width, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: tableView, attribute: .height, relatedBy: .equal, toItem: view, attribute: .height, multiplier: 1, constant: 0),
        ])
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { return 40 }
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let title = sectionTitles[section]
        let headerView = CustomSectionHeader(title: title)
        return headerView
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        if let tableView = view.subviews.first as? UITableView {
            tableView.frame = view.bounds
        }
    }
    
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sectionTitles.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sectionTitles[section] {
        case "Credits":
            return CreditsData.getCreditsData().count
        case "Acknowledgements":
            return 1
        default:
            return 0
        }
    }
    
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sectionTitles[section]
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseIdentifier = "Cell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier) ?? UITableViewCell(style: .value1, reuseIdentifier: reuseIdentifier)
        
        cell.selectionStyle = .default
        
        switch sectionTitles[indexPath.section] {
        case "Credits":
            let personCellIdentifier = "PersonCell"
            let personCell = tableView.dequeueReusableCell(withIdentifier: personCellIdentifier) as? PersonCell ?? PersonCell(style: .default, reuseIdentifier: personCellIdentifier)
            
            let developers = CreditsData.getCreditsData()
            let developer = developers[indexPath.row]
            
            personCell.configure(with: developer)
            if let arrowImage = UIImage(systemName: "arrow.up.forward")?.withTintColor(UIColor.tertiaryLabel, renderingMode: .alwaysOriginal) {
                personCell.accessoryView = UIImageView(image: arrowImage)
            }
            return personCell
            
        case "Acknowledgements":
            cell.textLabel?.text = "Licensing"
            cell.accessoryType = .disclosureIndicator
        default:
            break
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        switch sectionTitles[indexPath.section] {
        case "Credits":
            let developers = CreditsData.getCreditsData()
            let developer = developers[indexPath.row]
            if let socialLink = developer.socialLink {
                UIApplication.shared.open(socialLink, options: [:], completionHandler: nil)
            }
        case "Acknowledgements":
            let lView = LicensesViewController()
            navigationController?.pushViewController(lView, animated: true)
        default:
            break
        }
    }
    
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 2:
            return "Thank you to everyone who has contributed into making the tool ❤️"
        default:
            return nil
        }
    }
}

class CreditsData {
    static func getCreditsData() -> [CreditsPerson] {
        let N = CreditsPerson(name: "Nathan",
                              role: "NathanLR Dev",
                              pfpURL: URL(string: "https://github.com/verygenericname.png")!,
                              socialLink: URL(string: "https://twitter.com/dedbeddedbed")!)
        let T = CreditsPerson(name: "Mineek",
                              role: "Main Serotonin dev",
                              pfpURL: URL(string: "https://github.com/mineek.png")!,
                              socialLink: URL(string: "https://twitter.com/mineekdev")!)
        let r = CreditsPerson(name: "hrtowii/sacrosanctuary",
                              role: "2nd serotonin dev, jitterd",
                              pfpURL: URL(string: "https://github.com/hrtowii.png")!,
                              socialLink: URL(string: "https://twitter.com/htrowii")!)
        let O = CreditsPerson(name: "Samara",
                              role: "UI",
                              pfpURL: URL(string: "https://github.com/ssalggnikool.png")!,
                              socialLink: URL(string: "https://twitter.com/ssaIggnikool")!)
        let l = CreditsPerson(name: "DuyTranKhanh",
                              role: "Contributed SpringBoard hooks and launchd hooks, LiveContainer Hooks, Trollstore JB Env",
                              pfpURL: URL(string: "https://github.com/khanhduytran0.png")!,
                              socialLink: URL(string: "https://twitter.com/TranKha50277352")!)
        let L = CreditsPerson(name: "NSBedtime",
                              role: "launchd hax, helped out a ton!",
                              pfpURL: URL(string: "https://pbs.twimg.com/profile_images/1743473385235947520/exyLyEA5_400x400.jpg")!,
                              socialLink: URL(string: "https://twitter.com/NSBedtime")!)
        let e = CreditsPerson(name: "Nick Chan",
                              role: "Helped out a lot!",
                              pfpURL: URL(string: "https://github.com/asdfugil.png")!,
                              socialLink: URL(string: "https://twitter.com/riscv64")!)
        let R = CreditsPerson(name: "Alfie CG",
                              role: "insert_dylib, name, helped out a lot, kernel exploit from TrollInstallerX",
                              pfpURL: URL(string: "https://github.com/alfiecg24.png")!,
                              socialLink: URL(string: "https://twitter.com/alfiecg_dev")!)
        let s = CreditsPerson(name: "haxi0",
                              role: "Added initial log",
                              pfpURL: URL(string: "https://github.com/haxi0.png")!,
                              socialLink: URL(string: "https://haxi0.space/")!)
        let t = CreditsPerson(name: "tuancc",
                              role: "Roothide dpkg hook, advice",
                              pfpURL: URL(string: "https://github.com/roothider.png")!,
                              socialLink: URL(string: "https://twitter.com/roothideDev")!)
        let o = CreditsPerson(name: "opa334",
                              role: "Several hooks from Dopamine",
                              pfpURL: URL(string: "https://github.com/opa334.png")!,
                              socialLink: URL(string: "https://twitter.com/opa334dev")!)
        let d = CreditsPerson(name: "timbovill",
                              role: "Icon",
                              pfpURL: URL(string: "https://cdn.discordapp.com/avatars/858923165379199007/d556be3fb98bc7fc37f79c8cceb63b1e?size=1024")!,
                              socialLink: nil)
        
        return [N, T, r, O, d, l, L, e, R, s, t, o]
    }
}
