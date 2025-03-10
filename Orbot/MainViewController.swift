//
//  MainViewController.swift
//  Orbot
//
//  Created by Benjamin Erhart on 20.05.20.
//  Copyright © 2020 Guardian Project. All rights reserved.
//

import UIKit
import Tor
import IPtProxyUI
import MBProgressHUD
import NetworkExtension

class MainViewController: UIViewController {

	@IBOutlet weak var logBt: UIBarButtonItem? {
		didSet {
			logBt?.accessibilityLabel = NSLocalizedString("Open or Close Log", comment: "")
			logBt?.accessibilityIdentifier = "open_close_log"
		}
	}

	@IBOutlet weak var settingsBt: UIBarButtonItem? {
		didSet {
			settingsBt?.accessibilityLabel = L10n.settings
			settingsBt?.accessibilityIdentifier = "settings_menu"

			updateMenu()
		}
	}

	@IBOutlet weak var refreshBt: UIBarButtonItem? {
		didSet {
			refreshBt?.accessibilityLabel = L10n.newCircuits
		}
	}

	@IBOutlet weak var statusIcon: UIImageView!
	@IBOutlet weak var controlBt: UIButton!
	@IBOutlet weak var statusLb: UILabel!

	@IBOutlet weak var snowflakeProxyBt: UIButton! {
		didSet {
			snowflakeProxyBt.setTitle(NSLocalizedString("Content Blocker", comment: ""))
		}
	}

	@IBOutlet weak var versionLb: UILabel! {
		didSet {
			versionLb.text = L10n.version
		}
	}

	@IBOutlet weak var logContainer: UIView! {
		didSet {
			// Only round top right corner.
			logContainer.layer.cornerRadius = 9
			logContainer.layer.maskedCorners = [.layerMaxXMinYCorner]
		}
	}

	@IBOutlet weak var logSc: UISegmentedControl! {
		didSet {
			logSc.setTitle("Tor", forSegmentAt: 0)
			logSc.setTitle(L10n.bridges, forSegmentAt: 1)
			logSc.setTitle(L10n.circuits, forSegmentAt: 2)

#if DEBUG
			if Config.extendedLogging {
				logSc.insertSegment(withTitle: "SFP", at: 3, animated: false)
				logSc.insertSegment(withTitle: "VPN", at: 4, animated: false)
				logSc.insertSegment(withTitle: "LL", at: 5, animated: false)
				logSc.insertSegment(withTitle: "LC", at: 6, animated: false)
				logSc.insertSegment(withTitle: "WS", at: 7, animated: false)
			}
#endif
		}
	}

	@IBOutlet weak var logTv: UITextView!


	private let bridgesConfDelegate = SharedUtils()


	override func viewDidLoad() {
		super.viewDidLoad()

		let callback: (Notification) -> Void = { [weak self] notification in
			self?.updateUi(notification)
		}

		let nc = NotificationCenter.default
		nc.addObserver(forName: .vpnStatusChanged, object: nil, queue: .main, using: callback)
		nc.addObserver(forName: .vpnProgress, object: nil, queue: .main, using: callback)

		updateUi()
	}


	// MARK: Actions

	@IBAction func toggleLogs() {
		if logContainer.isHidden {
			logContainer.transform = CGAffineTransform(translationX: -logContainer.bounds.width, y: 0)
			logContainer.isHidden = false

			UIView.animate(withDuration: 0.5) {
				self.logContainer.transform = CGAffineTransform(translationX: 0, y: 0)
			} completion: { _ in
				self.changeLog()
			}
		}
		else {
			hideLogs()
		}
	}

	@IBAction func hideLogs() {
		if !logContainer.isHidden {
			UIView.animate(withDuration: 0.5) {
				self.logContainer.transform = CGAffineTransform(translationX: -self.logContainer.bounds.width, y: 0)
			} completion: { _ in
				self.logContainer.isHidden = true
				self.logContainer.transform = CGAffineTransform(translationX: 0, y: 0)

				Logger.tailFile(nil)
			}
		}
	}

	func updateMenu() {
		var group1 = [UIAction]()
		var group2 = [UIAction]()

		group1.append(UIAction(
			title: L10n.settings,
			image: UIImage(systemName: "gearshape"),
			handler: { [weak self] _ in
				self?.showSettings()
			}))
		group1.last?.accessibilityIdentifier = "settings"

		group1.append(UIAction(
			title: L10n.authCookies,
			image: UIImage(systemName: "key"),
			handler: { [weak self] _ in
				self?.showAuth()
			}))
		group1.last?.accessibilityIdentifier = "auth_cookies"

		group1.append(UIAction(
			title: L10n.bridgeConf,
			image: UIImage(systemName: "network.badge.shield.half.filled"),
			handler: { [weak self] _ in
				self?.changeBridges()
			}))
		group1.last?.accessibilityIdentifier = "bridge_configuration"

		if !Settings.apiAccessTokens.isEmpty {
			group1.append(UIAction(
				title: NSLocalizedString("API Access", comment: ""),
				image: UIImage(systemName: "lock.shield"),
				handler: { [weak self] _ in
					self?.showApiAccess()
				}))
			group1.last?.accessibilityIdentifier = "api_access"
		}

		group2.append(UIAction(
			title: NSLocalizedString("Content Blocker", comment: ""),
			image: UIImage(systemName: "checkerboard.shield")) { [weak self] _ in
				self?.showContentBlocker()
			})
		group2.last?.accessibilityIdentifier = "content_blocker"

		settingsBt?.menu = nil

		settingsBt?.menu = UIMenu(title: "", children: [
			UIMenu(title: "", options: .displayInline, children: group1),
			UIMenu(title: "", options: .displayInline, children: group2)
		])
	}

	func showSettings(_ sender: UIBarButtonItem? = nil) {
		present(inNav: SettingsViewController(), button: sender ?? settingsBt)
	}

	@discardableResult
	func showAuth(_ sender: UIBarButtonItem? = nil) -> AuthViewController {
		let vc = AuthViewController(style: .grouped)

		present(inNav: vc, button: sender ?? settingsBt)

		return vc
	}

	func changeBridges(_ sender: UIBarButtonItem? = nil) {
		let vc = BridgesConfViewController()
		vc.delegate = bridgesConfDelegate

		present(inNav: vc, button: sender ?? settingsBt)
	}

	@discardableResult
	func showApiAccess(_ sender: UIBarButtonItem? = nil) -> ApiAccessViewController {
		let vc = ApiAccessViewController(style: .grouped)

		present(inNav: vc, button: sender ?? settingsBt)

		return vc
	}

	@IBAction func refresh(_ sender: UIBarButtonItem? = nil) {
		let hud = MBProgressHUD.showAdded(to: view, animated: true)
		hud.mode = .determinate
		hud.progress = 0
		hud.label.text = L10n.newCircuits

		let showError = { (error: Error) in
			hud.progress = 1
			hud.label.text = L10n.error
			hud.detailsLabel.text = error.localizedDescription
			hud.hide(animated: true, afterDelay: 3)
		}

		VpnManager.shared.getCircuits { [weak self] circuits, error in
			if let error = error {
				return showError(error)
			}

			hud.progress = 0.5

			VpnManager.shared.closeCircuits(circuits) { success, error in
				if let error = error {
					return showError(error)
				}

				hud.progress = 1

				if self?.logContainer.isHidden == false && self?.logSc.selectedSegmentIndex == 1 {
					self?.changeLog()
				}

				hud.hide(animated: true, afterDelay: 0.5)
			}
		}
	}

	@IBAction func control() {
		SharedUtils.control(startOnly: false)
	}

	@IBAction func changeLog() {
		switch logSc.selectedSegmentIndex {
		case 1:
			// Shows the content of the Snowflake or Obfs4proxy log file.
			Logger.tailFile(Settings.transport.logFile, update)

		case 2:
			Logger.tailFile(nil)

			SharedUtils.getCircuits { [weak self] text in
				self?.logTv.text = text
				self?.logTv.scrollToBottom()
			}

#if DEBUG
		case 3:
			// Shows the content of the Snowflake Proxy log file.
			Logger.tailFile(FileManager.default.sfpLogFile, update)

		case 4:
			// Shows the content of the VPN log file.
			Logger.tailFile(FileManager.default.vpnLogFile, update)

		case 5:
			// Shows the content of the leaf log file.
			Logger.tailFile(FileManager.default.leafLogFile, update)

		case 6:
			// Shows the content of the leaf config file.
			Logger.tailFile(FileManager.default.leafConfFile, update)

		case 7:
			// Shows the content of the GCD webserver log file.
			Logger.tailFile(FileManager.default.wsLogFile, update)
#endif

		default:
			Logger.tailFile(FileManager.default.torLogFile, update)
		}
	}

	@IBAction func controlSnowflakeProxy() {
#if DEBUG
		if Config.snowflakeProxyExperiment {
			SharedUtils.controlSnowflakeProxy()
		}
		else {
			showContentBlocker()
		}
#else
		showContentBlocker()
#endif
	}

	@IBAction func showContentBlocker() {
		present(inNav: ContentBlockerViewController(), button: settingsBt)
	}


	// MARK: Observers

	@objc func updateUi(_ notification: Notification? = nil) {

		refreshBt?.isEnabled = VpnManager.shared.sessionStatus == .connected

		let (statusIconName, buttonTitle, statusText, sfpText) = SharedUtils.updateUi(notification)

		statusIcon.image = UIImage(named: statusIconName)
		controlBt.setTitle(buttonTitle)
		statusLb.attributedText = statusText

		logSc.setEnabled(Settings.transport != .none, forSegmentAt: 1)

#if DEBUG
		if Config.snowflakeProxyExperiment {
			snowflakeProxyBt.setTitle(sfpText)
		}
#endif
	}


	// MARK: Private Methods

	private func update(_ logText: String) {
		let atBottom = logTv.isAtBottom

		logTv.text = logText

		if atBottom {
			logTv.scrollToBottom()
		}
	}
}
