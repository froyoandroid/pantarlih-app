# Pantarlih Security & Race Condition Audit
**Date:** 2026-09-18  
**Scope:** Full application audit - security vulnerabilities, race conditions, data integrity

---

## EXECUTIVE SUMMARY

**CRITICAL**: 3 issues requiring immediate attention  
**HIGH**: 5 issues requiring near-term fixes  
**MEDIUM**: 7 issues for consideration  
**LOW**: 4 informational findings

**Overall Assessment**: The app demonstrates good security practices (parameterized queries, offline-only operation, permission gating) but has **critical race conditions** in the journal/database commit path and **insufficient protection of PII** in backups and crash logs.

---

## CRITICAL ISSUES

### C1. Journal-Database Race Condition Window
**File**: `lib/data/store.dart:426-428`  
**Severity**: CRITICAL - Data loss risk

```dart
await _appendJournal(event);      // Line 426: writes journal
journalWritten = true;
await _applyEvent(txn, event);   // Line 428: applies to DB (inside transaction)
```

**Problem**: Between journal write and DB commit, a crash leaves journal ahead of database. The `_recoveryRequired` flag (line 436) tries to handle this but:
1. Flag is in-memory only, lost on crash
2. Journal file already written, cannot be rolled back
3. Recovery on next launch may apply event twice if DB transaction partially succeeded
4. No idempotency guarantee on event replay

**Attack Vector**: Malicious actor could force-kill app repeatedly during commits to corrupt state.

**Impact**: Database inconsistency, duplicate entries, lost data.

**Recommendation**:
- Use WAL mode's transaction atomicity (already enabled, but not leveraged correctly)
- Write to journal INSIDE the SQLite transaction, or
- Use a `.pending` journal file renamed atomically after DB commit, or
- Add idempotency checks to `_applyEvent` (check if event_id already in log table before applying)

---

### C2. Unencrypted PII in Public Storage
**Files**: `lib/data/exchange.dart:66-92`, `lib/ui/admin_screen.dart:63-76`  
**Severity**: CRITICAL - Privacy violation

**Problem**:
1. Backup bundles (`cadangan_*.zip`) contain full database with NIK, names, birthdates
2. Excel exports contain same PII
3. Both written to public `Documents/Pantarlih<Desa>_<kode>/` unencrypted
4. Any app with storage permission can read these files
5. Share dialog warns user but doesn't prevent accidental sharing to internet services

**Evidence**:
```dart
// exchange.dart:86 - Backup written unencrypted
await tujuan.writeAsBytes(encoder.encode(archive), flush: true);

// admin_screen.dart:70 - Share allows any recipient
await SharePlus.instance.share(ShareParams(
    files: selected.map((f) => XFile(f.path)).toList(),
    subject: 'Pendataan DPS'));
```

**Attack Vector**: 
- Malware with storage permission exfiltrates all citizen data
- User accidentally shares to cloud service (Google Drive, WhatsApp backup)

**Recommendation**:
- Encrypt backup bundles with user-provided password (AES-256)
- Add "internal only" watermark to Excel exports
- Restrict share targets to specific apps (if Android APIs allow)
- Add second confirmation for sharing with remote services

---

### C3. Crash Logs Leak Sensitive Data
**File**: `lib/main.dart:41-51`  
**Severity**: CRITICAL - Information disclosure

```dart
void _catatCrash(Object error, StackTrace? stack) {
  await File('${dir.path}/crash_${fileStamp()}.log')
      .writeAsString('$error\n\n$stack', flush: true);
}
```

**Problem**:
1. Stack traces may contain NIK, names, or other PII from exception messages
2. Written to unencrypted file in app-private storage (survives on rooted devices)
3. Never rotated or cleaned up automatically
4. Error messages sometimes include user data (e.g., "Warga 1234567890123456 tidak ditemukan")

**Recommendation**:
- Sanitize error messages before logging (strip 16-digit numbers, names)
- Rotate crash logs (keep last 10, delete older)
- Encrypt crash logs
- Add opt-in for detailed crash reporting

---

## HIGH SEVERITY ISSUES

### H1. No File Locking on Journal Files
**File**: `lib/data/store.dart:445-465`  
**Severity**: HIGH - Data corruption risk

**Problem**: `_appendJournal` opens file in append mode but doesn't use file locking. If multiple instances or threads somehow access the same journal:
1. Interleaved writes could corrupt JSON lines
2. No protection against concurrent `_appendJournal` calls from different isolates (though `exclusive()` should prevent this in single-isolate app)

**Mitigating Factor**: `exclusive()` serializes all commits in the main isolate.

**Recommendation**: Add advisory file lock during journal append as defense-in-depth.

---

### H2. Checkpoint Can Skip Failed Events
**File**: `lib/data/store.dart:1194-1214`  
**Severity**: HIGH - Silent data loss

```dart
Future<void> _perbaruiCheckpoint() async {
  final maxId = intValue(rows.first['id']);
  // Advances checkpoint to highest applied event
  // BUT: if event 100 failed and event 101 succeeded,
  // checkpoint advances to 101, skipping 100 forever
}
```

**Problem**: Checkpoint advancement uses MAX(id) from log table, not "highest sequential applied". If event N fails but N+1 succeeds, checkpoint advances past N and it's never retried.

**Recommendation**: Track checkpoint as "highest ID where all prior IDs succeeded" or maintain a separate "failed events" set.

---

### H3. Import Path Traversal Vulnerability
**File**: `lib/data/spreadsheets.dart:46-68`  
**Severity**: HIGH - File system access

**Problem**: File names from imported workbooks used in paths without sanitization:

```dart
String slugWilayah(String nama) {
  final slug = nama.toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')  // Good: strips special chars
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.length <= 24 ? slug : slug.substring(0, 24);
}
```

This is used for **export** filenames, which is OK. But imported filenames are stored as-is in `sumber_file` column and could contain path traversal sequences.

**Mitigating Factor**: `sumber_file` only used for display and filtering, not for file operations.

**Recommendation**: Sanitize `sumber_file` on import to basename only.

---

### H4. No Rate Limiting on Database Operations
**File**: `lib/data/store.dart:388-443`  
**Severity**: HIGH - DoS potential

**Problem**: No throttling on `saveWarga`, `deleteWarga`, or other mutations. A malicious actor (or buggy UI code) could:
1. Trigger thousands of commits rapidly
2. Fill disk with journal files
3. Exhaust I/O, making app unresponsive
4. Create massive replay burden on next startup

**Recommendation**: Add per-second rate limit on commit operations (e.g., max 10/sec).

---

### H5. Backup Rotation Race Condition
**File**: `lib/data/exchange.dart:94-104`  
**Severity**: HIGH - File corruption

```dart
Future<void> _rotasiCadangan(Directory dir, int keep) async {
  final files = await dir.list().where(...).toList();
  files.sort((a, b) => b.path.compareTo(a.path));
  for (final old in files.skip(keep)) {
    await old.delete();  // No check if file is being read/written elsewhere
  }
}
```

**Problem**: Backup rotation deletes old files without checking if they're in use. If user is restoring from a backup while rotation runs, file could be deleted mid-read.

**Recommendation**: Use file locking or move-then-delete pattern.

---

## MEDIUM SEVERITY ISSUES

### M1. Memory Exhaustion in Search
**File**: `lib/ui/search_screen.dart:58-80`

```dart
final refs = await session.store.allReferensi(session.rw);
final rows = await session.store.allWarga();  // Loads ALL warga into memory
```

**Problem**: With 10,000+ warga entries, this could exhaust memory on low-end devices.

**Recommendation**: Implement pagination or streaming search.

---

### M2. No Database Encryption at Rest
**File**: `lib/data/store.dart:100-154`

**Problem**: SQLite database stored unencrypted in app-private directory. On rooted devices or with ADB access, full database is readable.

**Recommendation**: Use `sqflite_sqlcipher` for transparent encryption (requires key management).

---

### M3. Replay Attacks on Journal Events
**File**: `lib/data/store.dart:1054-1145`

**Problem**: Journal events have no HMAC or signature. A malicious actor with filesystem access could:
1. Modify journal files to inject fake events
2. Replay old events by copying journal files
3. Reorder events to create inconsistencies

**Mitigating Factor**: Requires rooted device or ADB access.

**Recommendation**: Sign journal events with HMAC-SHA256 using device-specific key.

---

### M4. No Input Sanitization on Names
**File**: `lib/ui/survey_form.dart:68-90`

```dart
name = TextEditingController(
    text: pilih([edit?['nama'], seed?['nama'], widget.initialName])
        .toUpperCase());  // Only transforms to uppercase, no sanitization
```

**Problem**: Names stored exactly as typed. Could include:
- Control characters (newlines, tabs)
- Unicode exploits (RTL overrides, homoglyphs)
- Excessive whitespace

**Impact**: Could break Excel exports, UI rendering, or create spoofing attacks.

**Recommendation**: Strip control characters, normalize whitespace, validate Unicode ranges.

---

### M5. Excel Formula Injection Risk
**File**: `lib/data/spreadsheets.dart:76-89`

**Problem**: When exporting to Excel, cell values starting with `=`, `+`, `-`, `@` could be interpreted as formulas by Excel, potentially executing arbitrary commands on recipient's machine.

**Example**: Name stored as `=cmd|'/c calc'!A1` becomes formula in Excel.

**Recommendation**: Prefix risky cells with single quote (`'`) or space when exporting.

---

### M6. Snapshot Restore Not Atomic
**File**: `lib/data/exchange.dart:110-142`

```dart
Future<RecoveryReport> pulihkanCadangan(AppStore store, Uint8List bytes) async {
  // Extracts snapshot, copies over current DB, replays journal
  // NOT atomic - crash mid-restore leaves corrupted state
}
```

**Recommendation**: Extract to temp location, verify integrity, then atomic rename.

---

### M7. NIK Validation Insufficient
**File**: `lib/core/nik.dart:6-35`

**Problem**: NIK validation is warning-only, not blocking:
```dart
if (!RegExp(r'^\d{16}$').hasMatch(nik)) {
  return ['NIK bukan 16 digit angka'];  // Warning, not error
}
```

Allows invalid NIKs to be stored. Also doesn't validate checksum (if NIK has one).

**Recommendation**: Make format validation blocking, add checksum validation.

---

## LOW SEVERITY / INFORMATIONAL

### L1. Debug MCP Toolkit in Production Risk
**File**: `lib/main.dart:19-25`

```dart
if (kDebugMode) {
  MCPToolkitBinding.instance
    ..initialize()
    ..initializeFlutterToolkit();
}
```

**Finding**: MCP toolkit properly gated behind `kDebugMode`, but has extensive app control capabilities when enabled.

**Recommendation**: Document that debug builds should never be distributed.

---

### L2. Permissive SQL Constraints
**File**: `lib/data/schema.dart:29-48`

```dart
jenis_kelamin TEXT CHECK (jenis_kelamin IN ('L','P')),
// But allows NULL
```

**Finding**: Many fields allow NULL when they shouldn't (e.g., `nik`, `kode_wilayah` should be NOT NULL).

**Recommendation**: Tighten constraints in schema v8.

---

### L3. Timestamp Injection Possible
**File**: `lib/data/store.dart:405-417`

```dart
final ts = timestamp();  // Generated at commit time
// But payload can override with 'dicatat_pada' or 'diubah_pada'
```

**Finding**: Caller-provided timestamps could create artificial backdating.

**Recommendation**: Always use server-side (commit-time) timestamp, ignore caller values.

---

### L4. No Version Pinning on Snapshots
**File**: `lib/data/store.dart:1248-1266`

**Finding**: Snapshots don't record app version or schema version in filename. Restoring very old snapshot to newer app version could fail silently.

**Recommendation**: Include schema version in snapshot metadata.

---

## RACE CONDITION ANALYSIS

### Safe Patterns ✓
1. **Exclusive queue** (store.dart:88-98): `_tail` future chain prevents concurrent commits
2. **Parameterized queries**: All SQL uses whereArgs, no string concatenation
3. **Transaction boundaries**: SQLite ACID properties properly used

### Unsafe Patterns ✗
1. **Journal-DB split**: Critical gap between journal write and DB commit (C1)
2. **File operations**: No locking on journal append, backup rotation (H1, H5)
3. **Checkpoint advancement**: Can skip failed events (H2)
4. **notifyListeners()**: Called after transaction, but observers see stale in-memory state until reload
5. **Search screen caching**: `cacheSkor` map accessed from build and async load (potential setState-after-dispose)

### Threading Model
- Single-isolate app (UI + DB on main isolate)
- `exclusive()` serializes DB operations
- File I/O is async but not parallelized per file
- **Risk**: Future Dart/Flutter multi-isolate DB access could break serialization assumptions

---

## SQL INJECTION ANALYSIS ✓

**Finding**: NO SQL injection vulnerabilities found.

All queries use parameterized form:
```dart
db.query('warga', where: 'id = ?', whereArgs: [id])  // Safe
db.rawQuery('SELECT ...', whereArgs)                  // Safe
```

Never uses string interpolation:
```dart
// NONE of this found:
db.rawQuery('SELECT * FROM warga WHERE id = $id')  // Vulnerable (not found)
```

**Grade**: A+ for SQL injection prevention.

---

## DATA PROTECTION ANALYSIS

### What's Protected ✓
- App-private storage (database, journal) requires root/ADB to access
- Storage permission requested only on export/import, not at startup
- No network calls (verified, no HTTP libraries imported)

### What's Exposed ✗
- **Public backups** unencrypted in Documents/ (C2)
- **Excel exports** unencrypted in Documents/ (C2)
- **Crash logs** with PII in app-private storage (C3)
- **Share functionality** allows PII to leave device (C2)

### Compliance Concerns
If this app is subject to GDPR, Indonesian PDP Law, or similar regulations:
- **Right to erasure**: Backups in Documents/ survive app uninstall
- **Data minimization**: Exports include all fields, no option to exclude sensitive ones
- **Consent**: Share dialog warns but doesn't get explicit opt-in
- **Breach notification**: No audit trail of when data was exported/shared

---

## RECOMMENDATIONS PRIORITY

### Immediate (This Week)
1. Fix C1: Make journal-DB commit atomic (add idempotency or use pending-file pattern)
2. Fix C2: Encrypt backup bundles or move to app-private storage
3. Fix C3: Sanitize crash logs to remove PII

### Near-Term (This Month)
1. Fix H2: Repair checkpoint logic to not skip failed events
2. Fix H4: Add rate limiting on commits
3. Fix M5: Prevent Excel formula injection on export

### Medium-Term (This Quarter)
1. Implement M2: Database encryption at rest (sqflite_sqlcipher)
2. Implement M3: Sign journal events with HMAC
3. Fix M6: Make snapshot restore atomic

### Long-Term
1. Add user-facing audit log ("Data accessed on X, exported on Y")
2. Implement selective export (allow excluding sensitive fields)
3. Add backup encryption with user password
4. Formal security review by external auditor

---

## TESTING RECOMMENDATIONS

### Concurrency Tests Needed
```dart
// Test simultaneous commits from UI
// Test journal replay during active commits  
// Test backup rotation during restore
// Test app kill at every line of _commitNow
```

### Fuzzing Targets
- Import parser (malformed Excel/CSV)
- Journal replay (corrupted JSON lines)
- NIK validation (Unicode, overflow)
- Name input (control chars, RTL, homoglyphs)

### Security Tests
- Attempt SQL injection via all input fields
- Attempt path traversal in import filenames
- Verify encrypted backups decrypt correctly
- Verify crash logs contain no PII

---

## CONCLUSION

The Pantarlih app has **good foundations** (offline-first, parameterized queries, permission gating) but needs **critical fixes** to:
1. Ensure journal-database atomicity (prevent data loss)
2. Protect PII in backups and exports (prevent privacy breaches)
3. Sanitize crash logs (prevent information disclosure)

**Risk Level**: Without fixes, the app is **not suitable for production use with real citizen data** due to data loss risk (C1) and privacy exposure (C2, C3).

**Estimated Fix Effort**: 3-5 days for critical issues, 2-3 weeks for high-severity issues.
