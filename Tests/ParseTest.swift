// Self-test: run `mmx quota show --output json`, parse it, print the result.
// Compile: swiftc -parse-as-library Tests/ParseTest.swift Sources/MiniMaxQuota/QuotaModel.swift -o /tmp/parsetest && /tmp/parsetest
import Foundation

@main
struct ParseTest {
    static func main() async {
        do {
            let r = try await QuotaFetcher.fetch()
            print("status: \(r.baseRespStatusCode) (\(r.baseRespStatusMsg))")
            print("models: \(r.modelRemains.count)")
            for q in r.modelRemains {
                print("  \(q.modelName):")
                print("    interval: \(q.intervalRemainingPercent)%  status=\(q.intervalStatus)")
                print("    weekly:   \(q.weeklyRemainingPercent)%  status=\(q.weeklyStatus)")
                print("    interval window: \(q.intervalStart) → \(q.intervalEnd)")
                print("    weekly window:   \(q.weeklyStart) → \(q.weeklyEnd)")
            }
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }
}
