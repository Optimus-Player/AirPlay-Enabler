//
//  PrivilegedHelperVersion.swift
//  AirPlayEnablerInterface
//
//  Created by Darren Mo on 2018-12-20.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Foundation

public class PrivilegedHelperVersion: NSObject, NSSecureCoding, Comparable {
   // MARK: - Properties

   public let buildNumber: Int

   public let majorVersion: Int
   public let minorVersion: Int
   public let patchVersion: Int

   // MARK: - Initialization

   public init(buildNumber: Int, majorVersion: Int, minorVersion: Int, patchVersion: Int) {
      self.buildNumber = buildNumber
      self.majorVersion = majorVersion
      self.minorVersion = minorVersion
      self.patchVersion = patchVersion

      super.init()
   }

   public convenience init?(buildNumberString: String, versionString: String) {
      guard let buildNumber = Int(buildNumberString) else {
         return nil
      }

      let versionStringComponents = versionString.split(separator: ".")
      guard versionStringComponents.count == 3 else {
         return nil
      }

      guard let majorVersion = Int(versionStringComponents[0]) else {
         return nil
      }
      guard let minorVersion = Int(versionStringComponents[1]) else {
         return nil
      }
      guard let patchVersion = Int(versionStringComponents[2]) else {
         return nil
      }

      self.init(buildNumber: buildNumber,
                majorVersion: majorVersion,
                minorVersion: minorVersion,
                patchVersion: patchVersion)
   }

   // MARK: - NSSecureCoding Conformance

   public static let supportsSecureCoding = true

   private static let buildNumberCoderKey = "mo.darren.optimus.player.mac.airplay-enabler.PrivilegedHelperVersion.buildNumber"
   private static let majorVersionCoderKey = "mo.darren.optimus.player.mac.airplay-enabler.PrivilegedHelperVersion.majorVersion"
   private static let minorVersionCoderKey = "mo.darren.optimus.player.mac.airplay-enabler.PrivilegedHelperVersion.minorVersion"
   private static let patchVersionCoderKey = "mo.darren.optimus.player.mac.airplay-enabler.PrivilegedHelperVersion.patchVersion"

   public func encode(with aCoder: NSCoder) {
      aCoder.encode(buildNumber, forKey: PrivilegedHelperVersion.buildNumberCoderKey)
      aCoder.encode(majorVersion, forKey: PrivilegedHelperVersion.majorVersionCoderKey)
      aCoder.encode(minorVersion, forKey: PrivilegedHelperVersion.minorVersionCoderKey)
      aCoder.encode(patchVersion, forKey: PrivilegedHelperVersion.patchVersionCoderKey)
   }

   public required init?(coder aDecoder: NSCoder) {
      guard aDecoder.containsValue(forKey: PrivilegedHelperVersion.buildNumberCoderKey) else {
         return nil
      }
      guard aDecoder.containsValue(forKey: PrivilegedHelperVersion.majorVersionCoderKey) else {
         return nil
      }
      guard aDecoder.containsValue(forKey: PrivilegedHelperVersion.minorVersionCoderKey) else {
         return nil
      }
      guard aDecoder.containsValue(forKey: PrivilegedHelperVersion.patchVersionCoderKey) else {
         return nil
      }

      self.buildNumber = aDecoder.decodeInteger(forKey: PrivilegedHelperVersion.buildNumberCoderKey)
      self.majorVersion = aDecoder.decodeInteger(forKey: PrivilegedHelperVersion.majorVersionCoderKey)
      self.minorVersion = aDecoder.decodeInteger(forKey: PrivilegedHelperVersion.minorVersionCoderKey)
      self.patchVersion = aDecoder.decodeInteger(forKey: PrivilegedHelperVersion.patchVersionCoderKey)
   }

   // MARK: - Comparable Conformance

   public static func <(lhs: PrivilegedHelperVersion, rhs: PrivilegedHelperVersion) -> Bool {
      return lhs.buildNumber < rhs.buildNumber
   }

   // MARK: - Hashable Conformance

   public override var hash: Int {
      return buildNumber.hashValue
   }

   // MARK: - Equatable Conformance

   public override func isEqual(_ object: Any?) -> Bool {
      guard let other = object as? PrivilegedHelperVersion else {
         return false
      }

      return self.buildNumber == other.buildNumber
   }

   public static func isMarketingVersionEqual(_ lhs: PrivilegedHelperVersion,
                                              _ rhs: PrivilegedHelperVersion) -> Bool {
      return
         lhs.majorVersion == rhs.majorVersion &&
            lhs.minorVersion == rhs.minorVersion &&
            lhs.patchVersion == rhs.patchVersion
   }

   // MARK: - CustomStringConvertible Conformance

   public override var description: String {
      return description(includingBuildNumber: true)
   }

   public var marketingDescription: String {
      return description(includingBuildNumber: false)
   }

   public func description(includingBuildNumber shouldIncludeBuildNumber: Bool) -> String {
      var description = "\(majorVersion).\(minorVersion).\(patchVersion)"

      if shouldIncludeBuildNumber {
         description += " (\(buildNumber))"
      }

      return description
   }
}
