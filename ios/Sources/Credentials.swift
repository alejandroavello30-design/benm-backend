import Foundation
import Security

enum Credentials {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "cl.radioequipo.benm",
         kSecAttrAccount as String: "team-code"]
    }
    static func read() -> String {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ code: String) {
        clear()
        var q = query
        q[kSecValueData as String] = Data(code.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
