//
//  PinningSessionDelegate.swift
//  SnowHaze
//

//  Copyright © 2018 Illotros GmbH. All rights reserved.
//

import Foundation


class PinningSessionDelegate: NSObject, URLSessionDelegate {
	static let pinnedHosts = ["api.snowhaze.com", "search.snowhaze.com"]

	private static let primaryAPICert = SecPolicyEvaluator.cert(named: "api")!
	private static let primarySearchCert = SecPolicyEvaluator.cert(named: "search")!
	
	static let pinnedCerts = [primaryAPICert, primarySearchCert]

	func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		let space = challenge.protectionSpace
		guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
			completionHandler(.performDefaultHandling, nil)
			return
		}
		guard PinningSessionDelegate.pinnedHosts.contains(space.host) else {
			completionHandler(.cancelAuthenticationChallenge, nil)
			return
		}
		let policy = SecPolicyEvaluator(domain: space.host, trust: space.serverTrust!)
		let certs = PinningSessionDelegate.pinnedCerts
		policy.evaluate(.strict) { result in
			if result && policy.pin(with: .certs(certs)) {
				completionHandler(.performDefaultHandling, nil)
			} else {
				completionHandler(.cancelAuthenticationChallenge, nil)
			}
		}
	}
}
