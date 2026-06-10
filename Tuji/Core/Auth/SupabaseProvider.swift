// Single SupabaseClient for the whole app. Reads URL + anon key from
// Info.plist (which gets them from xcconfig at build time).
//
// Persistence: supabase-swift v2 stores the session in Keychain by default
// on iOS, so the user stays signed in across launches without extra wiring.

import Foundation
import Supabase

enum SupabaseProvider {
    static let client: SupabaseClient = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let urlStr = info["TUJI_SUPABASE_URL"] as? String,
              let url = URL(string: urlStr),
              let key = info["TUJI_SUPABASE_ANON_KEY"] as? String,
              !key.isEmpty
        else {
            fatalError("""
            Missing TUJI_SUPABASE_URL or TUJI_SUPABASE_ANON_KEY in Info.plist.
            Check that Config/Secrets.xcconfig is populated.
            """)
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}
