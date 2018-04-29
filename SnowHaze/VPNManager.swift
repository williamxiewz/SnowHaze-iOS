//
//  VPNManager.swift
//  SnowHaze
//

//  Copyright © 2017 Illotros GmbH. All rights reserved.
//

import Foundation
import NetworkExtension

private let installedProfilesKey = "ch.illotros.ios.snowhaze.premium.vpn.profiles.installed"
private let ovpnProfilesKey = "ch.illotros.ios.snowhaze.premium.vpn.profiles.all.data" // called ...profiles.all.data for historical reasons
private let ipsecProfilesKey = "ch.illotros.ios.snowhaze.premium.vpn.profiles.ipsec.data"

private let lastProfileUpdateKey = "ch.illotros.ios.snowhaze.premium.vpn.profiles.lastprofileupdate"
private let lastProfileExpirationWarningKey = "ch.illotros.ios.snowhaze.premium.vpn.profiles.lastexpirationwarning"
private let selectedProfileKey = "ch.illotros.snowhaze.selectedIPSecProfile"

struct IPSecConfig: Equatable {
	let identity: String
	let psk: String
	let host: String

	public static func ==(_ lhs: IPSecConfig, _ rhs: IPSecConfig) -> Bool {
		return lhs.identity == rhs.identity && lhs.psk == rhs.psk && lhs.host == lhs.host
	}
}

protocol VPNProfile {
	var names: [String: String] { get }
	var flag: UIImage { get }
	var id: String { get }
	var hosts: [String] { get }
	var expiration: Date? { get }
	var hasProfile: Bool { get }
	var data: [String: Any] { get }

	func unchanged(since: VPNProfile) -> Bool
	func equals(_: VPNProfile) -> Bool
}

struct IPSecProfile: VPNProfile, Equatable {
	let names: [String: String]
	let flag: UIImage
	let id: String
	let hosts: [String]
	let configs: [IPSecConfig]
	let expiration: Date?

	public static func ==(_ lhs: IPSecProfile, _ rhs: IPSecProfile) -> Bool {
		return lhs.id == rhs.id
	}

	func equals(_ other: VPNProfile) -> Bool {
		return self == other as? IPSecProfile
	}

	func unchanged(since: VPNProfile) -> Bool {
		assert(self.equals(since))
		let other = since as! IPSecProfile
		guard expiration == other.expiration && configs.count == other.configs.count else {
			return false
		}
		return configs == other.configs
	}

	fileprivate init?(data: [String: Any]) {
		guard let id = data["id"] as? String else {
			return nil
		}
		self.id = id
		guard let names = data["names"] as? [String: String] else {
			return nil
		}
		self.names = names
		guard let hosts = data["hosts"] as? [String] else {
			return nil
		}
		self.hosts = hosts
		guard let flagBase64 = data["flag"] as? String, let flagData = Data(base64Encoded: flagBase64) else {
			return nil
		}
		guard let flag = UIImage(data: flagData) else {
			return nil
		}
		self.flag = flag
		if let expirationTimestamp = data["expiration"] as? Double {
			let date = Date(timeIntervalSince1970: expirationTimestamp)
			if date > Date() {
				expiration = date
				guard let rawConfigs = data["credentials"] as? [[String: String]], !rawConfigs.isEmpty else {
					return nil
				}
				let configs = rawConfigs.compactMap { data -> IPSecConfig? in
					guard let identity = data["identity"] else {
						return nil
					}
					guard let psk = data["psk"] else {
						return nil
					}
					guard let host = data["host"] else {
						return nil
					}
					return IPSecConfig(identity: identity, psk: psk, host: host)
				}
				guard configs.count == rawConfigs.count else {
					return nil
				}
				self.configs = configs
			} else {
				expiration = nil
				configs = []
			}
		} else {
			expiration = nil
			configs = []
		}
	}

	var hasProfile: Bool {
		assert((configs.isEmpty) == (expiration == nil))
		return !configs.isEmpty
	}

	var data: [String: Any] {
		var ret = [String: Any]()
		ret["id"] = id
		ret["names"] = names
		ret["hosts"] = hosts
		ret["credentials"] = configs.map { ["identity": $0.identity, "host": $0.host, "psk": $0.psk] }
		let flagData = UIImagePNGRepresentation(flag)!
		ret["flag"] = flagData.base64EncodedString()
		if let timestamp = expiration?.timeIntervalSince1970 {
			ret["expiration"] = timestamp
		}
		return ret
	}
}

struct OVPNProfile: VPNProfile, Equatable {
	let names: [String: String]
	let flag: UIImage
	let id: String
	let hosts: [String]
	let profile: String?
	let expiration: Date?
	let installedExpiration: Date?

	public static func ==(_ lhs: OVPNProfile, _ rhs: OVPNProfile) -> Bool {
		return lhs.id == rhs.id
	}

	func equals(_ other: VPNProfile) -> Bool {
		return self == other as? OVPNProfile
	}

	func unchanged(since: VPNProfile) -> Bool {
		assert(self.equals(since))
		let other = since as! OVPNProfile
		return profile == other.profile && expiration == other.expiration
	}

	fileprivate init?(data: [String: Any], installed: [String: Double]) {
		guard let id = data["id"] as? String else {
			return nil
		}
		self.id = id
		guard let names = data["names"] as? [String: String] else {
			return nil
		}
		self.names = names
		guard let hosts = data["hosts"] as? [String] else {
			return nil
		}
		self.hosts = hosts
		guard let flagBase64 = data["flag"] as? String, let flagData = Data(base64Encoded: flagBase64) else {
			return nil
		}
		guard let flag = UIImage(data: flagData) else {
			return nil
		}
		self.flag = flag
		if let expirationTimestamp = data["expiration"] as? Double {
			let date = Date(timeIntervalSince1970: expirationTimestamp)
			if date > Date() {
				expiration = date
				guard let profile = data["profile"] as? String else {
					return nil
				}
				self.profile = profile
			} else {
				expiration = nil
				profile = nil
			}
		} else {
			expiration = nil
			profile = nil
		}
		if let installed = installed[id] {
			installedExpiration = Date(timeIntervalSince1970: installed)
		} else {
			installedExpiration = nil
		}
	}

	var hasProfile: Bool {
		assert((profile != nil) == (expiration != nil))
		return profile != nil
	}

	var isInstalled: Bool {
		return installedExpiration != nil
	}

	var data: [String: Any] {
		var ret = [String: Any]()
		ret["id"] = id
		ret["names"] = names
		ret["hosts"] = hosts
		if let profile = profile {
			ret["profile"] = profile
		}
		let flagData = UIImagePNGRepresentation(flag)!
		ret["flag"] = flagData.base64EncodedString()
		if let timestamp = expiration?.timeIntervalSince1970 {
			ret["expiration"] = timestamp
		}
		return ret
	}
}

protocol VPNManagerDelegate: AnyObject {
	func vpnManager(_ manager: VPNManager, didChangeOVPNProfileListFrom from: [OVPNProfile], to: [OVPNProfile])
	func vpnManager(_ manager: VPNManager, didChangeIPSecProfileListFrom from: [IPSecProfile], to: [IPSecProfile])
}

class VPNManager {
	private(set) var ipsecManagerLoaded = false
	private var performWithLoadedVPNManager: [() -> Void]?
	private var lastIPSecCredSwap = Date.distantPast

	var selectedProfileID: String? = DataStore.shared.getString(for: selectedProfileKey) {
		didSet {
			DataStore.shared.set(selectedProfileID, for: selectedProfileKey)
		}
	}

	private init() {
		ovpnProfiles = []
		ipsecProfiles = []
		let ovpnJson = DataStore.shared.getString(for: ovpnProfilesKey) ?? "[]"
		let ipsecJson = DataStore.shared.getString(for: ipsecProfilesKey) ?? "[]"
		let rawOVPNArray = try! JSONSerialization.jsonObject(with: ovpnJson.data(using: .utf8)!)
		let rawIPSecNArray = try! JSONSerialization.jsonObject(with: ipsecJson.data(using: .utf8)!)
		let installed = installedProfiles
		let rawOVPNProfiles = (rawOVPNArray as! [[String: Any]]).map { OVPNProfile(data: $0, installed: installed) }
		let rawIPSecProfiles = (rawIPSecNArray as! [[String: Any]]).map { IPSecProfile(data: $0) }
		if !rawOVPNProfiles.contains(where: { $0 == nil }) {
			ovpnProfiles = rawOVPNProfiles.map { $0! }
		} else {
			DataStore.shared.delete(lastProfileUpdateKey)
			DataStore.shared.delete(ovpnProfilesKey)
		}

		if !rawIPSecProfiles.contains(where: { $0 == nil }) {
			ipsecProfiles = rawIPSecProfiles.map { $0! }
		} else {
			DataStore.shared.delete(lastProfileUpdateKey)
			DataStore.shared.delete(ipsecProfilesKey)
		}

		withLoadedManager { _ in
			if !SubscriptionManager.shared.hasSubscription {
				self.disconnect()
			}
		}
	}

	var profileExpirationWarningConfig: (multiple: Bool, expired: Bool)? {
		let instant = 0.0
		let week = 7.0 * 24 * 60 * 60
		let fiveDays = 5.0 * 24 * 60 * 60
		let lastWarning: TimeInterval
		if let timestamp = DataStore.shared.getDouble(for: lastProfileExpirationWarningKey) {
			lastWarning = Date(timeIntervalSince1970: timestamp).timeIntervalSinceNow
		} else {
			lastWarning = -Double.infinity
		}
		let expirations = ovpnProfiles.compactMap { $0.installedExpiration?.timeIntervalSinceNow }
		let expired = expirations.filter({ $0 <= instant && $0 >= lastWarning }).count
		let expiring = expirations.filter({ $0 <= week }).count

		if lastWarning >= -fiveDays {
			return nil
		} else if !SubscriptionManager.shared.stilHasSubscription(in: week) {
			return nil
		} else if expired > 0 {
			return (expired > 1, true)
		} else if expiring > 0 {
			return (expiring > 1, false)
		} else {
			return nil
		}
	}

	func didDisplayProfileExpirationWarning() {
		DataStore.shared.set(Date().timeIntervalSince1970, for: lastProfileExpirationWarningKey)
	}

	private(set) var isDownloading = false
	private var downloadCompletionHandlers = [(Bool) -> Void]()

	static let shared = VPNManager()

	private let urlSession = URLSession(configuration: .ephemeral, delegate: PinningSessionDelegate(), delegateQueue: nil)

	private(set) var ovpnProfiles: [OVPNProfile] {
		didSet {
			let rawArray = ovpnProfiles.map { $0.data }
			let jsonData = try! JSONSerialization.data(withJSONObject: rawArray)
			DataStore.shared.set(String(data: jsonData, encoding: .utf8), for: ovpnProfilesKey)
			delegate?.vpnManager(self, didChangeOVPNProfileListFrom: oldValue, to: ovpnProfiles)
		}
	}

	private(set) var ipsecProfiles: [IPSecProfile] {
		didSet {
			let rawArray = ipsecProfiles.map { $0.data }
			let jsonData = try! JSONSerialization.data(withJSONObject: rawArray)
			DataStore.shared.set(String(data: jsonData, encoding: .utf8), for: ipsecProfilesKey)
			delegate?.vpnManager(self, didChangeIPSecProfileListFrom: oldValue, to: ipsecProfiles)
		}
	}

	weak var delegate: VPNManagerDelegate?

	private var installedProfiles: [String: Double] {
		get {
			let installedJSON = DataStore.shared.getString(for: installedProfilesKey) ?? "{}"
			return try! JSONSerialization.jsonObject(with: installedJSON.data(using: .utf8)!) as! [String: Double]
		}
		set {
			let jsonData = try! JSONSerialization.data(withJSONObject: newValue)
			DataStore.shared.set(String(data: jsonData, encoding: .utf8), for: installedProfilesKey)
		}
	}

	func didInstall(_ profile: OVPNProfile) {
		assert(profile.hasProfile)
		let index = ovpnProfiles.index(where: { $0 == profile })!
		installedProfiles[profile.id] = profile.expiration!.timeIntervalSince1970
		let updated = OVPNProfile(data: profile.data, installed: installedProfiles)!
		ovpnProfiles[index] = updated
	}

	private var needsProfileUpdate: Bool {
		if ovpnProfiles.isEmpty || ipsecProfiles.isEmpty {
			return true
		}
		if !SubscriptionManager.shared.hasSubscription {
			return false
		}
		return ovpnProfiles.contains(where: { !$0.hasProfile }) || ipsecProfiles.contains(where: { !$0.hasProfile })
	}

	func updateProfileList(withCompletionHandler completionHandler: ((Bool) -> Void)?) {
		let baseURL = "https://api.snowhaze.com/index.php"
		var request: URLRequest
		let timestamp = DataStore.shared.getDouble(for: lastProfileUpdateKey) ?? -Double.infinity
		let date = Date(timeIntervalSince1970: timestamp)
		guard date.timeIntervalSinceNow < -24 * 60 * 60 || needsProfileUpdate else {
			if let handler = completionHandler {
				DispatchQueue.main.async {
					handler(false)
				}
			}
			return
		}
		let manager = SubscriptionManager.shared
		if manager.hasValidToken, let token = manager.authorizationToken {
			request = URLRequest(url: URL(string: baseURL)!)
			request.setFormEncoded(data: ["t": token, "v": "2", "action": "vpn"])
		} else if manager.hasSubscription {
			if PolicyManager.globalManager().autoUpdateAuthToken {
				SubscriptionManager.shared.updateAuthToken { success in
					if success {
						self.updateProfileList(withCompletionHandler: completionHandler)
					} else if let handler = completionHandler {
						handler(false)
					}
				}
			} else if let handler = completionHandler {
				handler(false)
			}
			return
		} else {
			request = URLRequest(url: URL(string: baseURL)!)
			request.setFormEncoded(data: ["v": "2", "action": "vpn"])
		}

		if let handler = completionHandler {
			downloadCompletionHandlers.append(handler)
		}

		guard !isDownloading else {
			return
		}

		isDownloading = true
		let dec = InUseCounter.network.inc()
		let task = urlSession.dataTask(with: request) { data, _, error in
			dec()
			guard let data = data, let dictionary = (try? JSONSerialization.jsonObject(with: data)) as? [String: [[String: Any]]] else {
				DispatchQueue.main.async {
					self.isDownloading = false
					self.downloadCompletionHandlers.forEach { $0(false) }
					self.downloadCompletionHandlers = []
				}
				return
			}
			DispatchQueue.main.async {
				let installed = self.installedProfiles
				guard let ovpn = dictionary["ovpn"] else {
					return
				}
				guard let ipsec = dictionary["ipsec"] else {
					return
				}
				let newOVPNProfiles = ovpn.compactMap { OVPNProfile(data: $0, installed: installed) }
				let ovpnSuccess = newOVPNProfiles.count == ovpn.count

				let newIPSecProfiles = ipsec.compactMap { IPSecProfile(data: $0) }
				let ipsecSuccess = newIPSecProfiles.count == ipsec.count

				self.isDownloading = false
				if ovpnSuccess {
					self.ovpnProfiles = newOVPNProfiles
				}

				if ipsecSuccess {
					self.ipsecProfiles = newIPSecProfiles
				}

				if ovpnSuccess && ipsecSuccess {
					DataStore.shared.set(Date().timeIntervalSince1970, for: lastProfileUpdateKey)
				}
				self.downloadCompletionHandlers.forEach { $0(ipsecSuccess && ovpnSuccess) }
				self.downloadCompletionHandlers = []
			}
		}
		task.resume()
	}
}

/// IPSec management
extension VPNManager {
	var ipsecConnected: Bool {
		switch NEVPNManager.shared().connection.status {
			case .connected:		return true
			case .connecting:		return true
			case .disconnected:		return false
			case .disconnecting:	return false
			case .invalid:			return false
			case .reasserting:		return true
		}
	}

	func withLoadedManager(perform block: @escaping (@escaping ()->Void) -> Void) {
		var retryCount = 0
		let reload: () -> Void = {
			guard retryCount < 3 else {
				return
			}
			retryCount += 1
			self.loadVPNManager {
				self.withLoadedManager(perform: block)
			}
		}
		guard ipsecManagerLoaded else {
			reload()
			return
		}
		block(reload)
	}

	private func saveManager(with reload: @escaping () -> Void, success: (() -> Void)? = nil) {
		NEVPNManager.shared().saveToPreferences { err in
			if let error = err {
				if #available(iOS 11, *) {
					let code = (error as NSError).code
					if (error as NSError).domain == "NEVPNErrorDomain" {
						switch code {
							case NEDNSProxyManagerError.configurationCannotBeRemoved.rawValue:
								fatalError("was not trying to remove config")
							case NEDNSProxyManagerError.configurationDisabled.rawValue:
								print("config disabled")
							case NEDNSProxyManagerError.configurationInvalid.rawValue:
								reload()
							case NEDNSProxyManagerError.configurationStale.rawValue:
								reload()
							default:
								print("unexpected error code \(code)")
						}
					} else {
						print("unexpected error domain \((error as NSError).domain), code \(code)")
					}
				}
			} else {
				success?()
			}
		}
	}

	private func loadVPNManager(completion: (() -> Void)? = nil) {
		guard performWithLoadedVPNManager == nil else {
			if let block = completion {
				performWithLoadedVPNManager!.append(block)
			}
			return
		}
		if let completion = completion {
			performWithLoadedVPNManager = [completion]
		} else {
			performWithLoadedVPNManager = []
		}
		NEVPNManager.shared().loadFromPreferences { error in
			DispatchQueue.main.async {
				if let error = error {
					if #available(iOS 11, *) {
						let code = (error as NSError).code
						if (error as NSError).domain == "NEVPNErrorDomain" {
							switch code {
								case NEDNSProxyManagerError.configurationCannotBeRemoved.rawValue:
									fatalError("was not trying to remove config")
								case NEDNSProxyManagerError.configurationDisabled.rawValue:
									print("config disabled")
								case NEDNSProxyManagerError.configurationInvalid.rawValue:
									print("config invalid")
								case NEDNSProxyManagerError.configurationStale.rawValue:
									fatalError("I was already trying to load config")
								default:
									print("unexpected error code \(code)")
							}
						} else {
							print("unexpected error domain \((error as NSError).domain), code \(code)")
						}
					}
					self.performWithLoadedVPNManager = nil
				} else {
					self.ipsecManagerLoaded = true
					for block in self.performWithLoadedVPNManager! {
						block()
					}
					self.performWithLoadedVPNManager = nil
				}
			}
		}
	}



	func disconnect() {
		VPNManager.shared.withLoadedManager { reload in
			let manager = NEVPNManager.shared()

			// don't create a profile just to disconnect
			guard !(manager.protocolConfiguration?.serverAddress ?? "").isEmpty else {
				return
			}

			manager.isOnDemandEnabled = false
			VPNManager.shared.saveManager(with: reload) {
				NEVPNManager.shared().connection.stopVPNTunnel()
			}
		}
	}

	private func clearSavedProfile() {
		withLoadedManager { reload in
			NEVPNManager.shared().removeFromPreferences { err in
				if let error = err {
					if #available(iOS 11, *) {
						let code = (error as NSError).code
						if (error as NSError).domain == "NEVPNErrorDomain" {
							switch code {
								case NEDNSProxyManagerError.configurationCannotBeRemoved.rawValue:
									reload()
								case NEDNSProxyManagerError.configurationDisabled.rawValue:
									print("config disabled")
								case NEDNSProxyManagerError.configurationInvalid.rawValue:
									break
								case NEDNSProxyManagerError.configurationStale.rawValue:
									reload()
								default:
									print("unexpected error code \(code)")
							}
						} else {
							print("unexpected error domain \((error as NSError).domain), code \(code)")
						}
					}
				} else {
					self.lastIPSecCredSwap = Date()
				}
			}
		}
	}

	func save(_ profile: IPSecProfile, enable: Bool = false, completion: (() -> Void)? = nil) {
		selectedProfileID = profile.id
		guard !profile.configs.isEmpty else {
			clearSavedProfile()
			return
		}
		lastIPSecCredSwap = Date()
		let config = profile.configs.randomElement

		let loc = NSLocalizedString("localization code", comment: "code used to identify the current locale")
		let name = profile.names[loc] ?? profile.names["en"] ?? profile.hosts.first ?? "?"

		VPNManager.shared.withLoadedManager { reload in
			let vpnManager = NEVPNManager.shared()

			let psk = KeyManager(name: "snowhaze.vpn.ipsec.psk.current")
			psk.set(key: config.psk)

			let ike = NEVPNProtocolIKEv2()
			ike.deadPeerDetectionRate = .none
			ike.serverAddress = config.host
			ike.remoteIdentifier = config.host
			ike.localIdentifier = config.identity
			ike.enablePFS = true

			ike.ikeSecurityAssociationParameters.encryptionAlgorithm = .algorithmAES256GCM
			ike.ikeSecurityAssociationParameters.integrityAlgorithm = .SHA512
			ike.ikeSecurityAssociationParameters.diffieHellmanGroup = .group16

			ike.childSecurityAssociationParameters.encryptionAlgorithm = .algorithmAES256GCM
			ike.childSecurityAssociationParameters.integrityAlgorithm = .SHA512
			ike.childSecurityAssociationParameters.diffieHellmanGroup = .group16

			if #available(iOS 11.0, *) {
				ike.minimumTLSVersion = .version1_2
			}

			ike.sharedSecretReference = psk.persistentReference!
			ike.disconnectOnSleep = false
			ike.authenticationMethod = .sharedSecret
			ike.useExtendedAuthentication = true

			let alwaysConnect = NEOnDemandRuleConnect()
			alwaysConnect.interfaceTypeMatch = .any

			vpnManager.onDemandRules = [alwaysConnect]
			vpnManager.protocolConfiguration = ike
			vpnManager.isEnabled = true
			vpnManager.isOnDemandEnabled = enable
			vpnManager.localizedDescription = name
			VPNManager.shared.saveManager(with: reload) {
				completion?()
			}
		}
	}

	func connect(with profile: IPSecProfile) {
		save(profile, enable: true) {
			try? NEVPNManager.shared().connection.startVPNTunnel()
		}
	}

	func swapLongRunningIPSecCreds() {
		let profile = VPNManager.shared.ipsecProfiles.first { $0.id == selectedProfileID }
		if ipsecConnected && lastIPSecCredSwap.timeIntervalSinceNow < -60 * 60 {
			if let profile = profile, SubscriptionManager.shared.hasSubscription {
				connect(with: profile)
			} else if SubscriptionManager.shared.hasSubscription {
				disconnect()
			} else {
				clearSavedProfile()
			}
		} else if !SubscriptionManager.shared.hasSubscription {
			clearSavedProfile()
		} else if let profile = profile, !profile.hasProfile {
			clearSavedProfile()
		}
	}
}