package app.dailychallenge.core

import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.locks.ReentrantLock

/**
 * Serializes every read, change and commit of one history folder: the app's edits, its sync
 * merge, widget taps and the widget account. A writer loads the store fresh from disk inside
 * the lock, so it never commits over a snapshot another writer has replaced since (the iPhone's
 * shared-store transaction). Threads of one process wait on a JVM lock; another process waits
 * on an advisory lock of a stable file that atomic replacement never swaps. Never hold it over
 * a network request.
 */
class StoreLock(directory: File) {
    private val file = File(directory, LOCK_FILE)
    private val local: ReentrantLock = locks.getOrPut(file.absoluteFile.normalize().path) { ReentrantLock() }

    fun <T> withLock(block: () -> T): T {
        local.lock()
        try {
            // Reentry on the same thread already holds the file lock, which a JVM cannot take twice.
            if (local.holdCount > 1) return block()
            file.parentFile?.mkdirs()
            RandomAccessFile(file, "rw").use { access ->
                access.channel.lock().use { return block() }
            }
        } finally {
            local.unlock()
        }
    }

    companion object {
        const val LOCK_FILE = ".store.lock"
        private val locks = ConcurrentHashMap<String, ReentrantLock>()
    }
}
