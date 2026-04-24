// CloudKit typed record codec — issue #70 (S7.2), extended in #71 (S7.3).
//
// Translates between Flutter's channel map representation and
// CloudKit's `CKRecord`. The Dart side owns the `CloudKitRecord` value
// type; this file is the sole place in the app that reaches into
// CloudKit typed setters/getters.
//
// Wire protocol (MUST match the Dart side in
// `method_channel_cloud_kit_source.dart`):
//
//   Each field crosses the channel as a 2-element `[typeTag, raw]`
//   array. typeTag is one of:
//     "string"   — raw = String
//     "int"      — raw = Int64 (Flutter sends NSNumber, Swift reads via
//                  the integer pathway; `NSNumber(value: Int64)` on the
//                  response side preserves integer vs double precision)
//     "double"   — raw = Double
//     "bool"     — raw = Bool
//     "dateTime" — raw = Int64 milliseconds-since-epoch (UTC). Swift
//                  decodes via `Date(timeIntervalSince1970: ms/1000.0)`.
//                  Response path: `NSDate.timeIntervalSince1970 * 1000`
//                  rounded to Int64.
//
//   Save method args map:
//     { "recordType": String,
//       "recordName": String,
//       "zoneName":   String?   — S7.3: optional. Null/missing = default
//                                  zone (back-compat with S7.2). Non-nil
//                                  = CKRecordZone.ID(zoneName: ...,
//                                    ownerName: CKCurrentUserDefaultName).
//       "fields": [String: [Any]]  (each value is [typeTag, raw]) }
//
//   Get method args map:
//     { "recordType": String,
//       "recordName": String,
//       "zoneName":   String?   — same semantics as save. }
//
//   Get method response (or null on record-not-found):
//     { "recordType": String, "recordName": String, "fields": ... }
//     Note: response does NOT echo "zoneName"; the caller already knows
//     which zone it asked for.
//
//   EnsureZoneExists method args map:
//     { "zoneName": String }
//     Handled by `EnsureZoneHandler` (separate file) against
//     `CKModifyRecordZonesOperation`. Idempotent — Apple's server
//     upserts by zoneID so creating an existing zone naturally
//     succeeds.
//
// Unknown typeTag on decode → throws `CloudKitCodecError.unknownTypeTag`;
// the caller surfaces as `FlutterError(code: "CK_UNKNOWN_TYPE_TAG")`.
// No silent fallback to String — matches the Dart side's trust rule.

import CloudKit
import Foundation

enum CloudKitCodecError: Error, CustomStringConvertible {
    case missingKey(String)
    case wrongType(field: String, expected: String, got: String)
    case unknownTypeTag(field: String, tag: String)
    case malformedField(field: String, reason: String)

    var description: String {
        switch self {
        case .missingKey(let k):
            return "CloudKitCodecError.missingKey(\(k))"
        case .wrongType(let f, let e, let g):
            return "CloudKitCodecError.wrongType(field: \(f), expected: \(e), got: \(g))"
        case .unknownTypeTag(let f, let t):
            return "CloudKitCodecError.unknownTypeTag(field: \(f), tag: \(t))"
        case .malformedField(let f, let r):
            return "CloudKitCodecError.malformedField(field: \(f), reason: \(r))"
        }
    }
}

public enum CloudKitRecordCodec {
    // Wire tag constants — mirror the Dart side's `_kTag*` constants.
    static let tagString = "string"
    static let tagInt = "int"
    static let tagDouble = "double"
    static let tagBool = "bool"
    static let tagDateTime = "dateTime"

    /// Decodes the inbound args map into a `CKRecord`.
    ///
    /// Expected shape: `{ "recordType": String, "recordName": String,
    /// "zoneName": String?, "fields": [String: [Any]] }`. When
    /// `zoneName` is nil/missing the record ID uses the default zone
    /// (S7.2 back-compat); when present it uses
    /// `CKRecordZone.ID(zoneName: ..., ownerName: CKCurrentUserDefaultName)`.
    public static func decodeRecord(from arguments: Any?) throws -> CKRecord {
        guard let args = arguments as? [String: Any] else {
            throw CloudKitCodecError.missingKey("arguments must be a [String: Any] map")
        }
        guard let recordType = args["recordType"] as? String else {
            throw CloudKitCodecError.missingKey("recordType")
        }
        guard let recordName = args["recordName"] as? String else {
            throw CloudKitCodecError.missingKey("recordName")
        }
        guard let rawFields = args["fields"] as? [String: Any] else {
            throw CloudKitCodecError.missingKey("fields")
        }

        // S7.3: optional zoneName. Missing → default zone. Present →
        // custom zone under the current user.
        let zoneName = args["zoneName"] as? String
        let recordID = recordID(forRecordName: recordName, zoneName: zoneName)
        let record = CKRecord(recordType: recordType, recordID: recordID)

        for (key, value) in rawFields {
            try applyField(to: record, key: key, wire: value)
        }
        return record
    }

    /// Constructs a `CKRecord.ID` scoped either to the default zone or
    /// to a custom zone owned by the current user.
    ///
    /// When `zoneName` is nil we use the no-zone-arg initializer, which
    /// lands in the default zone (`CKRecordZone.default()`). When non-nil
    /// we build `CKRecordZone.ID(zoneName:, ownerName: CKCurrentUserDefaultName)`.
    /// S7.3 scope: single-user, no shared/public zones.
    public static func recordID(forRecordName recordName: String, zoneName: String?) -> CKRecord.ID {
        guard let zoneName = zoneName else {
            return CKRecord.ID(recordName: recordName)
        }
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        return CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    /// Encodes a `CKRecord` into the response map Flutter expects.
    /// Inverse of `decodeRecord` — every encoded record must round-trip
    /// through the same wire protocol.
    public static func encodeRecord(_ record: CKRecord) throws -> [String: Any] {
        var fields: [String: [Any]] = [:]
        for key in record.allKeys() {
            let native = record[key]
            fields[key] = try encodeValue(native, field: key)
        }
        return [
            "recordType": record.recordType,
            "recordName": record.recordID.recordName,
            "fields": fields,
        ]
    }

    // MARK: - Internals

    private static func applyField(to record: CKRecord, key: String, wire: Any) throws {
        guard let pair = wire as? [Any], pair.count == 2 else {
            throw CloudKitCodecError.malformedField(
                field: key,
                reason: "expected 2-element [typeTag, value] array"
            )
        }
        guard let tag = pair[0] as? String else {
            throw CloudKitCodecError.malformedField(
                field: key,
                reason: "typeTag must be String"
            )
        }
        let raw = pair[1]

        switch tag {
        case tagString:
            guard let s = raw as? String else {
                throw CloudKitCodecError.wrongType(
                    field: key, expected: "String", got: String(describing: type(of: raw))
                )
            }
            record.setValue(s as NSString, forKey: key)

        case tagInt:
            // Flutter's standard codec surfaces Ints as either Int32 or
            // Int64 depending on magnitude. Accept either, store as
            // Int64 so the integer precision is preserved in the
            // CKRecord (CKRecord otherwise coerces bare numbers to
            // Double on some paths).
            let i64: Int64
            if let n = raw as? Int64 {
                i64 = n
            } else if let n = raw as? Int32 {
                i64 = Int64(n)
            } else if let n = raw as? Int {
                i64 = Int64(n)
            } else {
                throw CloudKitCodecError.wrongType(
                    field: key, expected: "Int/Int64", got: String(describing: type(of: raw))
                )
            }
            record.setValue(NSNumber(value: i64), forKey: key)

        case tagDouble:
            guard let d = raw as? Double else {
                throw CloudKitCodecError.wrongType(
                    field: key, expected: "Double", got: String(describing: type(of: raw))
                )
            }
            record.setValue(NSNumber(value: d), forKey: key)

        case tagBool:
            guard let b = raw as? Bool else {
                throw CloudKitCodecError.wrongType(
                    field: key, expected: "Bool", got: String(describing: type(of: raw))
                )
            }
            record.setValue(NSNumber(value: b), forKey: key)

        case tagDateTime:
            // Dart sends milliseconds-since-epoch as Int. Accept Int /
            // Int32 / Int64 variants the standard codec might surface.
            let ms: Int64
            if let n = raw as? Int64 {
                ms = n
            } else if let n = raw as? Int32 {
                ms = Int64(n)
            } else if let n = raw as? Int {
                ms = Int64(n)
            } else {
                throw CloudKitCodecError.wrongType(
                    field: key,
                    expected: "Int64 ms-since-epoch",
                    got: String(describing: type(of: raw))
                )
            }
            let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
            record.setValue(date as NSDate, forKey: key)

        default:
            throw CloudKitCodecError.unknownTypeTag(field: key, tag: tag)
        }
    }

    private static func encodeValue(_ native: Any?, field: String) throws -> [Any] {
        // Encode in Bool/Int/Double order mattering — `NSNumber` can
        // bridge to Bool AND Int AND Double; the canonical way to tell
        // a Boolean NSNumber apart from a numeric one is its
        // `objCType` ("c" for Bool). We use `CFGetTypeID` +
        // `CFBooleanGetTypeID()` which is the Apple-documented path.
        if native == nil {
            // CKRecord keys with nil values shouldn't happen — allKeys()
            // only lists keys with values. Surface loudly if it does.
            throw CloudKitCodecError.malformedField(
                field: field, reason: "nil value for key on CKRecord"
            )
        }
        if let s = native as? String {
            return [tagString, s]
        }
        if let d = native as? Date {
            let ms = Int64((d.timeIntervalSince1970 * 1000.0).rounded())
            return [tagDateTime, NSNumber(value: ms)]
        }
        if let n = native as? NSNumber {
            // Bool check first — NSNumber bridges Bool, Int, Double.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return [tagBool, n.boolValue]
            }
            // `objCType` is a C string like "q" (Int64), "i" (Int32),
            // "d" (Double), "f" (Float), "c" (Char/Bool), ...
            // Anything floating-point → Double; anything integer →
            // Int64. CKRecord doesn't distinguish Int32 vs Int64 on
            // reads — it gives us NSNumber and the Swift side picks.
            let objcType = String(cString: n.objCType)
            switch objcType {
            case "f", "d":
                return [tagDouble, n.doubleValue]
            default:
                return [tagInt, NSNumber(value: n.int64Value)]
            }
        }
        throw CloudKitCodecError.malformedField(
            field: field,
            reason: "unsupported CKRecord value type \(type(of: native!))"
        )
    }
}
