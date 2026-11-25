import Foundation
import os.lock

final class PCMFloatRingBuffer {
    struct WriteResult {
        let overwrittenFrames: Int
        let availableFrames: Int
        let capacity: Int
    }

    private let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0
    private var lock = os_unfair_lock_s()

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
        storage = UnsafeMutablePointer<Float>.allocate(capacity: self.capacity)
        storage.initialize(repeating: 0, count: self.capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    func clear() {
        os_unfair_lock_lock(&lock)
        readIndex = 0
        writeIndex = 0
        count = 0
        os_unfair_lock_unlock(&lock)
    }

    func write(_ source: UnsafePointer<Float>, frameCount: Int) -> WriteResult {
        guard frameCount > 0 else {
            return snapshot()
        }

        var overwrittenFrames = 0
        os_unfair_lock_lock(&lock)
        for frame in 0..<frameCount {
            if count == capacity {
                readIndex = (readIndex + 1) % capacity
                count -= 1
                overwrittenFrames += 1
            }

            storage[writeIndex] = source[frame]
            writeIndex = (writeIndex + 1) % capacity
            count += 1
        }
        let result = WriteResult(
            overwrittenFrames: overwrittenFrames,
            availableFrames: count,
            capacity: capacity
        )
        os_unfair_lock_unlock(&lock)
        return result
    }

    func read(into destination: UnsafeMutablePointer<Float>, frameCount: Int) -> Int {
        guard frameCount > 0 else {
            return 0
        }

        os_unfair_lock_lock(&lock)
        let framesToRead = min(frameCount, count)
        for frame in 0..<framesToRead {
            destination[frame] = storage[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        count -= framesToRead
        os_unfair_lock_unlock(&lock)
        return framesToRead
    }

    @discardableResult
    func discard(frameCount: Int) -> Int {
        guard frameCount > 0 else {
            return 0
        }

        os_unfair_lock_lock(&lock)
        let framesToDiscard = min(frameCount, count)
        readIndex = (readIndex + framesToDiscard) % capacity
        count -= framesToDiscard
        os_unfair_lock_unlock(&lock)
        return framesToDiscard
    }

    func snapshot() -> WriteResult {
        os_unfair_lock_lock(&lock)
        let result = WriteResult(
            overwrittenFrames: 0,
            availableFrames: count,
            capacity: capacity
        )
        os_unfair_lock_unlock(&lock)
        return result
    }
}
