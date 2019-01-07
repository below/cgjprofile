import Foundation

// There do not seem to be constants anywere in xOS:
// https://opensource.apple.com/source/kext_tools/kext_tools-425.1.3/security.c

let kSecOIDUserID          = "0.9.2342.19200300.100.1.1"
let kSecOIDCommonName               = "2.5.4.3"
let kSecOIDCountryName              = "2.5.4.6"
let kSecOIDOriganziationName        = "2.5.4.10"
let kSecOIDOrganizationalUnitName   = "2.5.4.11"

public class Mobileprovision {

    enum CMSError : Error {
        case create
        case update
        case finalize
        case copyContent
    }

    var Name : String
    var ExpirationDate : Date
    var Entitlements : [String:Any]
    var CreationDate : Date
    var AppIDName : String
    var UUID : String
    var TeamName : String
    var Platform : [String]?
    var ApplicationIdentifierPrefix : [String]
    var DeveloperCertificates : [Data]
    var TeamIdentifier : [String]
    var TimeToLive : Int
    var Version : Int
    
    public init? (_ plist : [String:Any]) {
        guard let uuid = plist["UUID"] as? String else { return nil }
        UUID = uuid
        
        guard let expirationDate = plist["ExpirationDate"] as? Date else { return nil }
        ExpirationDate = expirationDate
        
        if let entitlements = plist["Entitlements"] as? [String:Any] {
            Entitlements = entitlements
        } else { return nil}
        if let creationDate = plist["CreationDate"] as? Date {
            CreationDate = creationDate
        } else { return nil}
        if let appIDName = plist["AppIDName"] as? String {
            AppIDName = appIDName
        } else { return nil}
        if let teamName = plist["TeamName"] as? String {
            TeamName = teamName
        } else { return nil}
        if let applicationIdentifierPrefix = plist["ApplicationIdentifierPrefix"] as? [String] {
            ApplicationIdentifierPrefix = applicationIdentifierPrefix
        } else { return nil}
        if let certs = plist["DeveloperCertificates"] as? [Data] {
            // openssl x509 -noout -inform DER -subject
            DeveloperCertificates = certs
        } else { return nil}
        if let teamIdentifier = plist["TeamIdentifier"] as? [String] {
            TeamIdentifier = teamIdentifier
        } else { return nil}
        if let ttl = plist["TimeToLive"] as? Int {
            TimeToLive = ttl
        } else { return nil}
        if let version = plist["Version"] as? Int {
            Version = version
        } else { return nil}
        Platform = plist["Platform"] as? [String]
        Name = plist["Name"] as! String
    }
    
    // No clue why I must specify Foundation
    public convenience init?(url : Foundation.URL) {
        do {
            let provisionData = try Data(contentsOf: url)
            self.init(data: provisionData)
        }
        catch {
            return nil
        }
    }
    
    public convenience init?(data : Data) {
        do {
            let decodedProvision = try Mobileprovision.decodeCMS(data:data)
            let plist = try Mobileprovision.decodePlist (data: decodedProvision)
            self.init (plist)
        }
        catch {
            return nil
        }
    }
    
    public var daysToExpiration : Int {
        get {
            let expDate = self.ExpirationDate
            return Mobileprovision.daysToExpiration(for: expDate)
        }
    }
    
    public static func daysToExpiration(for expDate : Date) -> Int {
        let cal = Calendar.current
        let components = cal.dateComponents([Calendar.Component.day], from: Date(), to: expDate)
        return components.day ?? 0

    }
    
    enum X509Error : Error {
        case unableToDecodeItem
    }
    
    static func certificateDisplayName (data: Data) throws -> String {
        
        var commonName : String = "-"
        var organizationalUnit : String = "-"
        var organization : String = "-"
        
        guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
            throw X509Error.unableToDecodeItem
        }
        
        var error: Unmanaged<CFError>?
        guard let info = SecCertificateCopyValues(certificate, [kSecOIDX509V1SubjectName, kSecOIDX509V1SubjectNameStd, kSecOIDX509V1SubjectNameCStruct] as CFArray, &error) as? [CFString:[CFString:Any]] else {
            throw error!.takeRetainedValue() as Error
        }
        
        guard let subjectName = info[kSecOIDX509V1SubjectName]?[kSecPropertyKeyValue] as? [[CFString : String]] else {
            throw X509Error.unableToDecodeItem
        }
        
        for item in subjectName {
            
            guard let value = item[kSecPropertyKeyValue] else {
                throw X509Error.unableToDecodeItem
            }
            switch item[kSecPropertyKeyLabel] {
                case kSecOIDCommonName:
                    commonName = value
                case kSecOIDOriganziationName:
                    organization = value
                case kSecOIDOrganizationalUnitName:
                    organizationalUnit = value
                case kSecOIDUserID, kSecOIDCountryName:
                    continue
                default:
                    continue
                }
        }
        
        return "\(commonName) \(organizationalUnit) \(organization)"
    }
    
    static func certificateEnddate (data: Data) throws -> Date {
        
        guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
            throw X509Error.unableToDecodeItem
        }
        
        var error: Unmanaged<CFError>?
        guard let info = SecCertificateCopyValues(certificate, [kSecOIDX509V1ValidityNotAfter] as CFArray, &error) as? [CFString:[CFString:Any]] else {
            throw error!.takeRetainedValue() as Error
        }
        
        guard let value = info[kSecOIDX509V1ValidityNotAfter]?[kSecPropertyKeyValue] as? NSNumber else {
            throw X509Error.unableToDecodeItem
        }
        
        let date = Date(timeIntervalSinceReferenceDate: value.doubleValue)
        
        return date
    }
    
    public static func decodeCMS (data : Data) throws -> Data {
        var decoder : CMSDecoder?
        guard CMSDecoderCreate(&decoder) == noErr, let cmsDecoder = decoder else {
            throw CMSError.create
        }
        
        guard data.withUnsafeBytes({ (bytes) -> OSStatus in
            CMSDecoderUpdateMessage(cmsDecoder, bytes, data.count)
        }) == noErr else {
            throw CMSError.update
        }
        
        guard CMSDecoderFinalizeMessage(cmsDecoder) == noErr else {
            throw CMSError.finalize
        }
        
        var output : CFData?
        guard CMSDecoderCopyContent(cmsDecoder, &output) == noErr else {
            throw CMSError.copyContent
        }
        
        return output! as Data
    }
    
    public static func decodePlist (data : Data) throws -> [String:Any] {
        return try PropertyListSerialization.propertyList(from:data, options: [], format: nil) as! [String:Any]
    }

}


