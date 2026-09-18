# Security and Race Condition Audit Report
**Pantarlih Kalitorong App**  
**Date:** 2026-09-18  
**Auditor:** AI Security Analysis

---

## Executive Summary

Comprehensive security and race condition audit of the Pantarlih offline-first Flutter app for DPS data collection. The app handles sensitive personal data (NIK, names, birth dates, addresses) with SQLite storage and journal-based durability.

**Overall Assessment:** MEDIUM RISK  
**Critical Issues:** 1  
**High Issues:** 3  
**Medium Issues:** 5  
**Low Issues:** 4

---

## 1. CRITICAL ISSUES

### 1.1 Journal Corruption Leading to Data Loss (CRITICAL)
**Location:** `lib/data/store.dart:435-442`

**Issue:**  
The `_commitNow` method has a critical race condition where journal write succeeds but database transaction fails, setting `_recoveryRequired = true` and blocking all future writes until manual rebuild.

```dart
var journalWritten = false;
try {
  // ... journal append happens inside transaction
  await _appendJournal(event);
  journalWritten = true;
  await _applyEvent(txn, event);  // ← If this fails...
} catch (e) {
  if (journalWritten) {
    _recoveryRequired = true;  // ← App becomes read-only
    throw AppException('Jurnal sudah tersimpan, tetapi database gagal diperbarui...');
  }
}
```

**Risk:**  
- Journal written but SQLite transaction rolls back → inconsistent state
- Subsequent writes blocked until rebuild, but user sees no clear recovery path
- Loss of data entered after the failure until rebuild completes
- Field workers may continue survey work unaware the app is silently refusing writes

**Recommendation:**  
1. Move `_appendJournal` **outside** the transaction (journal as write-ahead log, not part of transaction)
2. Order: append journal → commit transaction → on transaction failure, mark journal event as "failed" or rotate the journal
3. Add startup recovery that detects journal events not in log table and re-applies them
4. Expose `_recoveryRequired` in UI with prominent banner and one-tap rebuild button

**Severity:** CRITICAL (data loss, app becomes unusable)

---

## 2. HIGH SEVERITY ISSUES

### 2.1 File Path Traversal in Import Archive (HIGH)
**Location:** `lib/data/exchange.dart:110-142` (`pulihkanCadangan`)

**Issue:**  
Archive extraction does not validate file paths. Malicious zip containing entries like `../../../etc/passwd` or `journal/../../../data/other.db` would write outside the intended directory.

```dart
for (final file in arsip.files) {
  final nama = file.name;
  if (nama.startsWith('journal/') && nama.endsWith('.jsonl')) {
    await File('${masuk.path}/journal/$nama')  // ← No path validation
        .writeAsBytes(file.content as Uint8List, flush: true);
  }
}
```

**Attack Vector:**  
1. Attacker creates malicious `cadangan_xxx.zip` with path traversal entries
2. User imports via "Pulihkan Cadangan" feature
3. Files written to arbitrary locations in app sandbox or device storage

**Recommendation:**  
```dart
// Sanitize archive member names
String _sanitizePath(String name) {
  final parts = name.split('/');
  // Remove .. and . components
  final safe = parts.where((p) => p.isNotEmpty && p != '.' && p != '..').toList();
  return safe.join('/');
}

// In pulihkanCadangan:
final nama = _sanitizePath(file.name);
if (!nama.startsWith('journal/')) continue;  // Reject if sanitization removed prefix
```

**Severity:** HIGH (arbitrary file write within app sandbox)

---

### 2.2 SQL Injection via Dynamic Table Name (HIGH)
**Location:** `lib/data/store.dart:326-329`

**Issue:**  
`_maxId` uses unvalidated table name in raw SQL query. While current callers only pass hardcoded strings, the API is unsafe and could be exploited if refactored.

```dart
Future<int> _maxId(DatabaseExecutor txn, String table) async {
  final rows =
      await txn.rawQuery('SELECT COALESCE(MAX(id), 0) AS id FROM $table');
  return intValue(rows.first['id']);
}
```

**Risk:**  
If `table` is ever sourced from journal events, user input, or import files, attacker could inject: `warga; DELETE FROM warga; --` leading to data destruction.

**Recommendation:**  
```dart
Future<int> _maxId(DatabaseExecutor txn, String table) async {
  // Whitelist valid tables
  const validTables = {'warga', 'referensi', 'log', 'lokasi', 'setelan', 'urutan_id'};
  if (!validTables.contains(table)) {
    throw AppException('Invalid table name: $table');
  }
  final rows =
      await txn.rawQuery('SELECT COALESCE(MAX(id), 0) AS id FROM $table');
  return intValue(rows.first['id']);
}
```

Apply same validation to `_nextId` (line 332) and any other dynamic table name usage.

**Severity:** HIGH (potential SQL injection leading to data loss)

---

### 2.3 Unprotected Storage Permission Exposure (HIGH)
**Location:** `android/app/src/main/AndroidManifest.xml:3-5`

**Issue:**  
App declares `MANAGE_EXTERNAL_STORAGE` permission, which grants broad access to entire device storage including other apps' public data.

```xml
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
```

**Risk:**  
- Excessive permission for stated functionality (only needs Documents folder access)
- Google Play may reject or flag app as potentially harmful
- If compromised (via dependency vulnerability), attacker gets full storage access
- User trust issue (permission prompt is very broad)

**Recommendation:**  
1. For Android 10+: Use scoped storage with `getExternalStoragePublicDirectory(DIRECTORY_DOCUMENTS)` or MediaStore API
2. Remove `MANAGE_EXTERNAL_STORAGE`
3. Keep `READ/WRITE_EXTERNAL_STORAGE` for Android ≤9 only (already scoped with `maxSdkVersion="29"`)
4. Use `permission_handler` only when export/import is actually triggered

**Severity:** HIGH (excessive permission, user trust, Play Store compliance)

---

## 3. MEDIUM SEVERITY ISSUES

### 3.1 Race Condition in Concurrent Reorder Operations (MEDIUM)
**Location:** `lib/data/store.dart:776-807` (`reorderWarga`)

**Issue:**  
While `exclusive()` serializes operations at AppStore level, multiple UI screens can simultaneously trigger reorder on same RT, causing stale reads.

**Scenario:**  
1. User A reads RT 01 warga list (10 items)
2. User B opens same RT, reads same list
3. User A reorders item 3 → item 1 (operation commits)
4. User B reorders item 5 → item 2 (reads stale `_wargaRt` that doesn't reflect A's changes)
5. Both operations write to journal, but order calculations based on stale state

**Current Mitigation:**  
`exclusive()` prevents concurrent database writes, but doesn't prevent stale reads before the exclusive operation begins.

**Recommendation:**  
```dart
Future<void> reorderWarga(int id, int? beforeId, int? afterId) async {
  final extras = <RecordMap>[];
  await _commit('REORDER', 'warga', (txn, ts) async {
    // All reads happen inside transaction, after exclusive lock acquired
    final row =
        (await txn.query('warga', where: 'id = ?', whereArgs: [id])).first;
    final rw = row['rw'] as int;
    final rt = row['rt'] as int;
    
    // Verify beforeId/afterId still exist (stale reference detection)
    final anchor = beforeId ?? afterId;
    if (anchor != null) {
      final anchorExists = await txn.query('warga', 
          where: 'id = ? AND rw = ? AND rt = ?', 
          whereArgs: [anchor, rw, rt]);
      if (anchorExists.isEmpty) {
        throw AppException('Posisi anchor sudah berubah. Muat ulang daftar.');
      }
    }
    
    final others = (await _wargaRt(txn, rw, rt))
        .where((r) => r['id'] != id).toList();
    // ... rest of logic
  }, extras: (_) => extras);
}
```

**Severity:** MEDIUM (data integrity, rare in single-user offline app but possible)

---

### 3.2 Journal File Handle Leak Risk (MEDIUM)
**Location:** `lib/data/store.dart:445-465` (`_appendJournal`)

**Issue:**  
Journal append opens file handle twice (once for length check, once for append) without guaranteed cleanup on crash.

```dart
final handle = await file.open(mode: FileMode.append);
try {
  final length = await handle.length();
  if (length > 0) {
    final reader = await file.open();  // ← Second handle
    try {
      await reader.setPosition(length - 1);
      if (await reader.readByte() != 10) await handle.writeByte(10);
    } finally {
      await reader.close();
    }
  }
  await handle.writeString('${jsonEncode(event)}\n');
  await handle.flush();
} finally {
  await handle.close();
}
```

**Risk:**  
- If exception occurs between `reader.close()` and `handle.close()`, `handle` leaks
- On Android, too many open file descriptors can crash app or prevent future file operations
- Journal corruption if flush fails but file remains open

**Recommendation:**  
```dart
Future<void> _appendJournal(RecordMap event) async {
  final date = event['ts'].toString().substring(0, 10);
  final file = File('${root.path}/journal/$date.jsonl');
  
  // Use single handle approach
  final content = '${jsonEncode(event)}\n';
  final bytes = utf8.encode(content);
  
  RandomAccessFile? handle;
  try {
    handle = await file.open(mode: FileMode.append);
    final length = await handle.length();
    
    // Ensure previous line has newline
    if (length > 0) {
      await handle.setPosition(length - 1);
      if (await handle.readByte() != 10) {
        await handle.writeByte(10);
      }
      await handle.setPosition(length);  // Reset to end for append
    }
    
    await handle.writeFrom(bytes);
    await handle.flush();
  } finally {
    await handle?.close();
  }
}
```

**Severity:** MEDIUM (file handle exhaustion, journal corruption on crash)

---

### 3.3 No NIK Validation Leading to Duplicate Citizens (MEDIUM)
**Location:** `lib/data/store.dart:653-660` (`_validateWarga`)

**Issue:**  
Validation only checks that `nama` is non-empty. NIK (national ID number) is not validated for:
- Format (should be 16 digits)
- Uniqueness (same NIK can exist multiple times)
- Checksum validity

```dart
void _validateWarga(RecordMap fields) {
  if ('${fields['nama'] ?? ''}'.trim().isEmpty) {
    throw AppException('Nama wajib diisi');
  }
  if (intValue(fields['rt']) <= 0 || intValue(fields['rw']) <= 0) {
    throw AppException('RT dan RW wajib berupa bilangan positif');
  }
  // No NIK validation!
}
```

**Risk:**  
- Duplicate NIKs lead to incorrect voter counts (one person counted twice)
- Typos in NIK go undetected
- Invalid NIKs cause data rejection at regional aggregation level

**Recommendation:**  
```dart
void _validateWarga(RecordMap fields) {
  if ('${fields['nama'] ?? ''}'.trim().isEmpty) {
    throw AppException('Nama wajib diisi');
  }
  if (intValue(fields['rt']) <= 0 || intValue(fields['rw']) <= 0) {
    throw AppException('RT dan RW wajib berupa bilangan positif');
  }
  
  final nik = fields['nik']?.toString() ?? '';
  if (nik.isNotEmpty) {
    // Use existing nik.dart validation
    final nikValidation = validasiNIK(nik);
    if (nikValidation != null) {
      throw AppException('NIK tidak valid: $nikValidation');
    }
    
    // Check uniqueness (exclude self in edit mode)
    final existing = await db.query('warga', 
        where: 'nik = ? AND id != ?', 
        whereArgs: [nik, fields['id'] ?? -1]);
    if (existing.isNotEmpty) {
      throw AppException('NIK sudah terdaftar atas nama ${existing.first['nama']}');
    }
  }
}
```

Note: This requires making `_validateWarga` async and adding proper NIK validation to `lib/core/nik.dart` if not already present.

**Severity:** MEDIUM (data quality, duplicate records)

---

### 3.4 Insecure Backup Encryption (MEDIUM)
**Location:** `lib/data/exchange.dart:66-92` (`tulisCadangan`)

**Issue:**  
Backup ZIP files containing sensitive personal data (NIK, names, addresses) are stored unencrypted in public `Documents/` folder.

```dart
final arsip = Archive();
arsip.addFile(ArchiveFile('pantarlih.db', db.length, db));
// ... add journal files
final zipped = ZipEncoder().encode(arsip);
final out = File('${tujuan.path}/cadangan_${fileStamp()}.zip');
await out.writeAsBytes(zipped!, flush: true);
```

**Risk:**  
- Anyone with device access can extract ZIP and read citizen data
- ADB pull, file manager, USB transfer exposes data
- Violates data protection principles (personal data should be encrypted at rest)
- Lost/stolen device = data breach

**Recommendation:**  
1. Use `archive` package's password-protected ZIP:
```dart
final zipped = ZipEncoder().encode(arsip, password: userPassword);
```
2. Store encryption key in secure storage (flutter_secure_storage)
3. Prompt for password on first export, store hashed version
4. Alternative: Use platform encryption (Android Keystore) to encrypt ZIP bytes

**Severity:** MEDIUM (data exposure, privacy compliance)

---

### 3.5 Unvalidated Excel Import Data (MEDIUM)
**Location:** `lib/data/spreadsheets.dart` and `lib/data/store.dart:1391-1418` (`kembalikanWarga`)

**Issue:**  
Imported Excel/CSV data is not sanitized before database insertion. While parameterized queries prevent SQL injection, malicious content can still cause issues:
- Extremely long strings (DOS via memory exhaustion)
- Special characters breaking UI rendering
- Malformed dates causing parsing errors

**Recommendation:**  
```dart
RecordMap _sanitizeImportRow(RecordMap row) {
  const maxStringLength = 1000;
  
  return {
    'nik': _sanitizeString(row['nik'], maxLen: 16),
    'nama': _sanitizeString(row['nama'], maxLen: 200, required: true),
    'jenis_kelamin': _sanitizeGender(row['jenis_kelamin']),
    'tempat_lahir': _sanitizeString(row['tempat_lahir'], maxLen: 100),
    'tgl_lahir': _sanitizeDate(row['tgl_lahir']),
    'desa': _sanitizeString(row['desa'], maxLen: 100),
    'rt': _sanitizeInt(row['rt'], min: 1, max: 999),
    'rw': _sanitizeInt(row['rw'], min: 1, max: 999),
    'keterangan': _sanitizeString(row['keterangan'], maxLen: 500),
  };
}
```

**Severity:** MEDIUM (DOS, data integrity)

---

## 4. LOW SEVERITY ISSUES

### 4.1 Crash Logs Contain Sensitive Stack Traces (LOW)
**Location:** `lib/main.dart:39-52` (`_catatCrash`)

**Issue:**  
Crash logs written to `recovered/crash_<stamp>.log` may contain sensitive data from stack traces (NIK values, names, database paths).

**Recommendation:**  
Sanitize stack traces before writing, or encrypt crash logs.

**Severity:** LOW (requires physical device access)

---

### 4.2 Debug-signed APK Allows Arbitrary Installation (LOW)
**Location:** Build configuration

**Issue:**  
Release APKs are signed with debug key, allowing anyone to build and install modified versions.

**Recommendation:**  
Use proper release signing for production builds.

**Severity:** LOW (intentional for single-device sideload, but document the risk)

---

### 4.3 No Rate Limiting on Journal Replay (LOW)
**Location:** `lib/data/store.dart:1054-1145` (`_replay`)

**Issue:**  
Malicious journal with millions of events could cause DOS during startup replay.

**Recommendation:**  
Add progress reporting and timeout for replay operations exceeding reasonable size (e.g., > 100k events).

**Severity:** LOW (requires compromised journal file)

---

### 4.4 INTERNET Permission Removal May Break Dependencies (LOW)
**Location:** `android/app/src/main/AndroidManifest.xml:2`

**Issue:**  
```xml
<uses-permission android:name="android.permission.INTERNET" tools:node="remove" />
```

While intended to enforce offline-first, some dependencies (e.g., crash reporting, analytics) may fail silently if added later.

**Recommendation:**  
Document this restriction prominently in AGENTS.md. Review all dependencies for network usage before adding.

**Severity:** LOW (design choice, just needs documentation)

---

## 5. RACE CONDITION ANALYSIS

### 5.1 Exclusive Queue Pattern (GOOD)
**Location:** `lib/data/store.dart:88-98`

```dart
Future<T> exclusive<T>(Future<T> Function() action) {
  final completer = Completer<T>();
  _tail = _tail.then((_) async {
    try {
      completer.complete(await action());
    } catch (e, st) {
      completer.completeError(e, st);
    }
  });
  return completer.future;
}
```

**Assessment:** ✅ CORRECT  
Serializes all database operations through a single queue. Prevents concurrent writes.

**Potential Issue:**  
If an operation hangs, entire queue blocks. No timeout mechanism.

**Recommendation:**  
Add operation timeout:
```dart
Future<T> exclusive<T>(Future<T> Function() action, {Duration timeout = const Duration(seconds: 30)}) {
  final completer = Completer<T>();
  _tail = _tail.then((_) async {
    try {
      completer.complete(await action().timeout(timeout));
    } catch (e, st) {
      completer.completeError(e, st);
    }
  });
  return completer.future;
}
```

---

### 5.2 ChangeNotifier Pattern (MEDIUM RISK)
**Location:** `lib/data/store.dart:72` (extends ChangeNotifier)

**Issue:**  
`notifyListeners()` called after database commits but outside transaction. If listener triggers another database operation immediately, serialization is correct but UI may see intermediate state.

**Example:**
```dart
// In _commitNow:
final result = await db.transaction((txn) async {
  // ... database changes
});
notifyListeners();  // ← Listeners fire here
return result;
```

If a listener calls another write operation, it queues correctly via `exclusive()`, but listeners don't see atomic batches.

**Recommendation:**  
Document that listeners should only read state, never trigger writes. Or batch notifications:
```dart
bool _notificationPending = false;

void _scheduleNotification() {
  if (_notificationPending) return;
  _notificationPending = true;
  scheduleMicrotask(() {
    _notificationPending = false;
    notifyListeners();
  });
}
```

---

### 5.3 Snapshot Rotation Race (LOW RISK)
**Location:** `lib/data/store.dart:1039-1052` (`_rotateSnapshot`)

**Issue:**  
Multiple snapshot operations could race during rotation (both reading dir.list(), both deleting same files).

**Mitigation:**  
All snapshot operations go through `exclusive()`, so rotation is serialized.

**Assessment:** ✅ PROTECTED

---

### 5.4 Journal File Date Boundary Race (LOW RISK)
**Location:** `lib/data/store.dart:445-465`

**Issue:**  
If two operations commit exactly at midnight (date change), both might:
1. Check `2026-09-17.jsonl` length
2. Append to `2026-09-17.jsonl`
3. But one should have created `2026-09-18.jsonl`

**Mitigation:**  
Operations are serialized through `exclusive()`, so date is re-evaluated for each operation.

**Assessment:** ✅ PROTECTED (but timestamps could still span midnight within single operation)

---

## 6. RECOMMENDATIONS SUMMARY

### Immediate Actions (CRITICAL/HIGH)
1. **Fix journal/transaction race** (§1.1): Move journal append outside transaction
2. **Validate archive paths** (§2.1): Add path sanitization to `pulihkanCadangan`
3. **Whitelist SQL table names** (§2.2): Validate `table` parameter in `_maxId`/_nextId`
4. **Reduce storage permissions** (§2.3): Remove `MANAGE_EXTERNAL_STORAGE`

### Short-term (MEDIUM)
5. **Add stale reference checks** (§3.1): Verify reorder anchors in transaction
6. **Fix journal file handling** (§3.2): Use single file handle pattern
7. **Implement NIK validation** (§3.3): Check format and uniqueness
8. **Encrypt backups** (§3.4): Add password protection to ZIP files
9. **Sanitize import data** (§3.5): Validate lengths and formats

### Long-term (LOW)
10. **Add operation timeouts** (§5.1): Prevent hung operations from blocking queue
11. **Sanitize crash logs** (§4.1): Remove sensitive data before writing
12. **Document debug signing** (§4.2): Clarify security posture in README

---

## 7. TESTING RECOMMENDATIONS

### Security Test Cases
1. **Path traversal:** Import ZIP with `../../../etc/passwd` entry
2. **SQL injection:** Modify journal event with table name `warga; DROP TABLE warga; --`
3. **Concurrent reorder:** Simulate two devices editing same RT simultaneously
4. **Journal corruption recovery:** Kill app during `_commitNow`, verify recovery
5. **Large import:** Import Excel with 100k rows, 10MB cells
6. **Backup extraction:** Verify public ZIP files are readable by other apps

### Race Condition Test Cases
1. **Rapid commits:** Submit 1000 warga entries as fast as possible, verify all journaled
2. **Concurrent snapshots:** Trigger backup + manual snapshot simultaneously
3. **Midnight boundary:** Commit operations at 23:59:59, verify journal date handling
4. **Listener loops:** Listener triggers write, verify no deadlock

---

## 8. COMPLIANCE NOTES

### Data Protection (GDPR/Local Equivalent)
- ❌ Unencrypted storage of personal data in public folder
- ✅ No automatic transmission (offline-first)
- ⚠️  Backup files not encrypted at rest
- ✅ Manual export only (no telemetry)

### Android Best Practices
- ❌ Excessive storage permission (`MANAGE_EXTERNAL_STORAGE`)
- ✅ No INTERNET permission (enforced offline)
- ✅ `allowBackup="false"` (prevents cloud backup of sensitive data)
- ✅ Debug signing documented as intentional

---

## Conclusion

The Pantarlih app demonstrates strong concurrency control through the `exclusive()` queue pattern and comprehensive journal-based durability. However, several critical issues around journal/transaction atomicity, file path validation, and permission scope need immediate attention.

The offline-first architecture reduces network attack surface, but local file security (unencrypted backups, path traversal) and data validation (NIK uniqueness, import sanitization) require hardening before deployment to additional devices or sharing backup files.

Primary focus: **Fix §1.1 (journal race) and §2.1-2.3 (injection/permissions) before production use.**
