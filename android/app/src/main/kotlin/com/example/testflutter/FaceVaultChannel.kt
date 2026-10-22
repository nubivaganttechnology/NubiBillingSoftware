package com.example.testflutter

import android.content.ContentValues
import android.content.Context
import android.content.pm.ApplicationInfo
import android.database.sqlite.SQLiteDatabase
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.Build
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.KeyInfo
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.util.UUID
import java.util.TimeZone
import org.json.JSONObject
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import kotlin.math.abs

/** Separate SQLite store: encrypted metadata/vectors, no images or sync access.
 * Hardware backing depends on the device; this does not attest the keystore. */
class FaceVaultChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "nubibill/face_vault")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val alias = "NubiBill.FaceVault.AES.v1"
    private var database: SQLiteDatabase? = null

    init {
        channel.setMethodCallHandler { call, result ->
            worker.execute {
                try {
                    if (call.method.startsWith("fixture")) requireFixture()
                    if (call.method != "fixtureEnvironment") requireTenant(call.argument<String>("tenantId"))
                    val answer: Any? = when (call.method) {
                        "fixtureEnvironment" -> mapOf("packageId" to context.packageName,
                            "androidApi" to Build.VERSION.SDK_INT, "model" to Build.MODEL)
                        "fixtureKeyInfo" -> {
                            val info = SecretKeyFactory.getInstance("AES", "AndroidKeyStore")
                                .getKeySpec(key(), KeyInfo::class.java) as KeyInfo
                            mapOf("insideSecureHardware" to info.isInsideSecureHardware,
                                "securityLevel" to if (Build.VERSION.SDK_INT >= 31) info.securityLevel else -1)
                        }
                        "fixtureTamper" -> {
                            val target = validFixtureKey(call.argument<String>("key"))
                            db().query("vault_records", arrayOf("ciphertext"), "record_key = ?", arrayOf(target), null, null, null).use {
                                check(it.moveToFirst())
                                val blob = it.getBlob(0)
                                blob[blob.size - 1] = (blob.last().toInt() xor 1).toByte()
                                db().update("vault_records", ContentValues().apply { put("ciphertext", blob) }, "record_key = ?", arrayOf(target))
                            }
                            null
                        }
                        "fixtureTransplant" -> {
                            val source = validFixtureKey(call.argument<String>("source"))
                            val target = validFixtureKey(call.argument<String>("target"))
                            db().query("vault_records", arrayOf("iv", "ciphertext"), "record_key = ?", arrayOf(source), null, null, null).use {
                                check(it.moveToFirst())
                                check(db().update("vault_records", ContentValues().apply {
                                    put("iv", it.getBlob(0)); put("ciphertext", it.getBlob(1))
                                }, "record_key = ?", arrayOf(target)) == 1)
                            }
                            null
                        }
                        "fixtureLoseKey" -> {
                            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(alias)
                            null
                        }
                        "read" -> read(validKey(call.argument<String>("key")))
                        "write" -> {
                            write(validKey(call.argument<String>("key")), validValue(call.argument<String>("value")))
                            null
                        }
                        "readBytes" -> readBytes(validKey(call.argument<String>("key")))
                        "writeBytes" -> {
                            val key = validKey(call.argument<String>("key"))
                            val bytes = call.argument<ByteArray>("bytes") ?: throw IllegalArgumentException("Missing bytes")
                            require(bytes.size <= 2097152) { "Value exceeds 2MB limit" }
                            writeBytes(key, bytes)
                            null
                        }
                        "listKeys" -> {
                            val prefix = call.argument<String>("prefix") ?: "face."
                            val keys = mutableListOf<String>()
                            db().rawQuery("SELECT record_key FROM vault_records WHERE record_key LIKE ?", arrayOf("$prefix%")).use { cursor ->
                                while (cursor.moveToNext()) {
                                    keys.add(cursor.getString(0))
                                }
                            }
                            keys
                        }
                        "compareAndSwap" -> {
                            val key = validKey(call.argument<String>("key"))
                            val expected = call.argument<String>("expected")
                            val value = validValue(call.argument<String>("value"))
                            val db = db()
                            db.beginTransaction()
                            try {
                                val matches = read(key) == expected
                                if (matches) write(key, value)
                                db.setTransactionSuccessful()
                                matches
                            } finally { db.endTransaction() }
                        }
                        "delete" -> {
                            db().delete("vault_records", "record_key = ?", arrayOf(validKey(call.argument<String>("key"))))
                            null
                        }
                        "deviceId" -> {
                            purgeExpired()
                            read("device.id") ?: UUID.randomUUID().toString().also { write("device.id", it) }
                        }
                        "timeZoneId" -> TimeZone.getDefault().id
                        "checkClock" -> checkClock()
                        "confirmDeviceTime" -> {
                            val boot = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
                            check(boot >= 0)
                            write("clock.anchor", "${System.currentTimeMillis()}|${SystemClock.elapsedRealtime()}|$boot")
                            null
                        }
                        "reset" -> {
                            // Logical deletion plus key destruction; flash erasure is not guaranteed.
                            db().delete("vault_records", null, null)
                            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(alias)
                            db().execSQL("VACUUM")
                            null
                        }
                        else -> throw IllegalArgumentException("Unsupported operation")
                    }
                    main.post { result.success(answer) }
                } catch (_: Exception) {
                    // Do not log exceptions, identifiers, plaintext, vectors or encryption keys.
                    main.post { result.error("FACE_VAULT_UNAVAILABLE", "Protected local store unavailable", null) }
                }
            }
        }
    }

    private fun validKey(value: String?): String {
        require(value != null && Regex("^[A-Za-z0-9._-]{1,160}$").matches(value))
        return value
    }

    // Destructive synthetic-test hooks cannot run in the billing app, including
    // its debug builds, or in any non-debug installation.
    private fun requireFixture() {
        check(context.packageName.endsWith(".attendancefixture"))
        check(context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0)
    }

    private fun validFixtureKey(value: String?): String {
        val valid = validKey(value)
        require(valid.startsWith("fixture."))
        return valid
    }

    private fun validValue(value: String?): String {
        require(value != null && value.toByteArray(Charsets.UTF_8).size <= 262144)
        return value
    }

    // A shop kiosk is provisioned for one tenant, including that tenant's outlets.
    // This nonsecret hash also permits owner recovery when the keystore key is lost.
    // Reset preserves the binding; another tenant cannot erase or reopen the vault.
    private fun requireTenant(tenant: String?) = synchronized(FaceVaultChannel::class.java) {
        require(tenant != null && Regex("^[A-Za-z0-9_-]{1,100}$").matches(tenant))
        val dir = File(context.noBackupFilesDir, "face_vault").apply { mkdirs() }
        val file = File(dir, "tenant_binding")
        val digest = MessageDigest.getInstance("SHA-256").digest(tenant.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        if (file.exists()) check(file.readText() == digest) else file.writeText(digest)
    }

    private fun db(): SQLiteDatabase {
        database?.let { return it }
        val dir = File(context.noBackupFilesDir, "face_vault").apply { mkdirs() }
        return SQLiteDatabase.openOrCreateDatabase(File(dir, "biometric_v1.sqlite"), null).also {
            check(it.version == 0 || it.version == 1)
            // These PRAGMAs return rows. Android's SQLite API rejects them via
            // execSQL on current releases; consume and verify the actual result.
            it.rawQuery("PRAGMA secure_delete = ON", null).use { cursor ->
                check(cursor.moveToFirst() && cursor.getInt(0) == 1)
            }
            it.rawQuery("PRAGMA journal_mode = DELETE", null).use { cursor ->
                check(cursor.moveToFirst() && cursor.getString(0).equals("delete", ignoreCase = true))
            }
            it.execSQL("CREATE TABLE IF NOT EXISTS vault_records (record_key TEXT PRIMARY KEY NOT NULL, iv BLOB NOT NULL, ciphertext BLOB NOT NULL)")
            it.version = 1
            database = it
        }
    }

    private fun key(): SecretKey {
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keys.getKey(alias, null) as? SecretKey)?.let { return it }
        // Never silently generate a replacement key over unreadable records.
        db().rawQuery("SELECT COUNT(*) FROM vault_records", null).use {
            check(it.moveToFirst() && it.getInt(0) == 0)
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).setRandomizedEncryptionRequired(true).build())
        return generator.generateKey()
    }

    private fun aad(recordKey: String) = "NubiBill.FaceVault.v1|$recordKey".toByteArray(Charsets.UTF_8)

    private fun read(recordKey: String): String? {
        db().query("vault_records", arrayOf("iv", "ciphertext"), "record_key = ?", arrayOf(recordKey), null, null, null).use {
            if (!it.moveToFirst()) return null
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, it.getBlob(0)))
            cipher.updateAAD(aad(recordKey))
            val plain = cipher.doFinal(it.getBlob(1))
            return try { String(plain, Charsets.UTF_8) } finally { plain.fill(0) }
        }
    }

    private fun write(recordKey: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key()) // Fresh platform-generated IV.
        cipher.updateAAD(aad(recordKey))
        val plain = value.toByteArray(Charsets.UTF_8)
        val encrypted = try { cipher.doFinal(plain) } finally { plain.fill(0) }
        val values = ContentValues().apply {
            put("record_key", recordKey); put("iv", cipher.iv); put("ciphertext", encrypted)
        }
        check(db().insertWithOnConflict("vault_records", null, values, SQLiteDatabase.CONFLICT_REPLACE) != -1L)
    }

    private fun readBytes(recordKey: String): ByteArray? {
        db().query("vault_records", arrayOf("iv", "ciphertext"), "record_key = ?", arrayOf(recordKey), null, null, null).use {
            if (!it.moveToFirst()) return null
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, it.getBlob(0)))
            cipher.updateAAD(aad(recordKey))
            return cipher.doFinal(it.getBlob(1))
        }
    }

    private fun writeBytes(recordKey: String, plain: ByteArray) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(aad(recordKey))
        val encrypted = cipher.doFinal(plain)
        val values = ContentValues().apply {
            put("record_key", recordKey); put("iv", cipher.iv); put("ciphertext", encrypted)
        }
        check(db().insertWithOnConflict("vault_records", null, values, SQLiteDatabase.CONFLICT_REPLACE) != -1L)
    }

    private fun checkClock(): Boolean {
        val wall = System.currentTimeMillis()
        val elapsed = SystemClock.elapsedRealtime()
        val boot = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
        val prior = read("clock.anchor")?.split('|')
        if (prior == null || prior.size != 3) {
            if (wall > 1704067200000L) {
                write("clock.anchor", "$wall|$elapsed|$boot")
                return true
            }
            return false
        }
        if (boot >= 0 && prior[2].toInt() != boot && wall > 1704067200000L) {
            write("clock.anchor", "$wall|$elapsed|$boot")
            return true
        }
        if (boot < 0 || prior[2].toInt() != boot || elapsed < prior[1].toLong() ||
            abs((wall - prior[0].toLong()) - (elapsed - prior[1].toLong())) > 120000L) {
            if (wall > 1704067200000L) {
                write("clock.anchor", "$wall|$elapsed|$boot")
                return true
            }
            return false
        }
        write("clock.anchor", "$wall|$elapsed|$boot")
        return true
    }

    private fun purgeExpired() {
        val expired = mutableListOf<String>()
        val photosToDelete = mutableListOf<String>()
        db().rawQuery("SELECT record_key FROM vault_records WHERE record_key LIKE 'face.template.%'", null).use { cursor ->
            while (cursor.moveToNext()) {
                val recordKey = cursor.getString(0)
                val payload = read(recordKey) ?: continue
                try {
                    val expiry = JSONObject(payload).optLong("retentionUntilEpochMillis", 0L)
                    if (expiry > 0L && expiry <= System.currentTimeMillis()) {
                        expired.add(recordKey)
                        photosToDelete.add(recordKey.replace("face.template.", "face.photo."))
                    }
                } catch (_: Exception) {
                    // Non-JSON or corrupted record - ignore during purge
                }
            }
        }
        for (recordKey in expired) db().delete("vault_records", "record_key = ?", arrayOf(recordKey))
        for (photoKey in photosToDelete) db().delete("vault_records", "record_key = ?", arrayOf(photoKey))
    }

    fun close() {
        channel.setMethodCallHandler(null)
        worker.execute { database?.close(); database = null }
        worker.shutdown()
    }
}
