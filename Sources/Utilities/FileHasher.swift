import Foundation
import CryptoKit

enum FileHasher {
    static func partialHash(of url: URL, byteLimit: Int = 4096, timeout: Duration = .seconds(10)) async -> Data? {
        await raceAgainstTimeout(timeout) {
            guard let handle = try? FileHandle(forReadingFrom: url),
                  let bytes = try? handle.read(upToCount: byteLimit) else {
                return nil
            }
            try? handle.close()
            return Data(SHA256.hash(data: bytes))
        }
    }

    static func fullHash(of url: URL, timeout: Duration = .seconds(120)) async -> Data? {
        await raceAgainstTimeout(timeout) {
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                return nil
            }
            var hasher = SHA256()
            while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            try? handle.close()
            return Data(hasher.finalize())
        }
    }

    private static func raceAgainstTimeout(_ timeout: Duration, work: @escaping @Sendable () -> Data?) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                    DispatchQueue.global(qos: .utility).async {
                        continuation.resume(returning: work())
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
