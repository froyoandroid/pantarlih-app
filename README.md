# Pantarlih Kalitorong

Aplikasi Flutter/Dart untuk Android, satu pengguna dan perangkat, sepenuhnya offline. Mendata sesuai KK asli tanpa menghitung umur atau menentukan kelayakan warga.

## Jalankan / build

Toolchain: Flutter 3.35.7 / Dart 3.9.2, Java 21, Android SDK 36, NDK 27.0.12077973. Dependensi dikunci di `pubspec.lock`.

```sh
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`. Build release lokal menggunakan signing key debug Android; cocok untuk sideload/perangkat tunggal, bukan publikasi Play Store. Gunakan keystore produksi yang dipertahankan untuk distribusi dan pembaruan jangka panjang. Jangan uninstall untuk memperbarui; install APK dengan tanda tangan yang sama di atas versi lama.

## Penggunaan

1. Instal APK (Android 7.0+), buka aplikasi, izinkan akses berkas. Pada Android 11+, aktifkan “Izinkan akses untuk mengelola semua file”, lalu kembali ke aplikasi. Android 7–10 menggunakan izin penyimpanan biasa.
2. Impor workbook. Untuk file yang diberikan, pilih sheet `RT 03` (189 warga), `RT 04` (123), dan `RT 05` (192) satu per satu: total 504. Jangan impor `REKAP`. Kolom disarankan otomatis, baris data pertama adalah 2. Periksa pratinjau dan konfirmasi RT setiap sheet.
3. Beranda → Ganti RT/RW. Pilih wilayah yang sedang dikerjakan. Pergantian wilayah membuat snapshot dan Excel otomatis lokal sebelum menerapkan sesi baru.
4. Cari nama minimal 3 karakter, pilih kandidat atau BUAT BARU. Jalur tanggal lahir menampilkan semua kecocokan di RW aktif. Isi nama, NIK, JK, tempat/tanggal lahir sesuai KK. Mode kertas dipilih di layar pencarian.
5. Simpan langsung per orang. NIK harus 16 digit angka; prefix, tanggal/JK, dan duplikat hanya peringatan. Duplikat dapat dibuka untuk koreksi atau tetap disimpan. Catatan bebas tidak dikategorikan, diparsing, atau digunakan untuk pencarian/penilaian.
6. Daftar Sisa memungkinkan tanda abu-abu manual. Riwayat menampilkan 20 input terakhir; edit, lepas tautan, dan tautkan ulang tersedia di form.
7. Ekspor & Pemulihan → pilih cakupan dan buat Excel. File DPS, PENDING, DUPLIKAT_NIK, dan KONFLIK_RT dibuat bersama. Berbagi selalu memerlukan aksi dan konfirmasi eksplisit.

## Lokasi dan keamanan data

Semua berkas berada di penyimpanan publik `Documents/PantarlihKalitorong/`:

```text
pantarlih.db           SQLite (WAL)
journal/               JSONL append-only, per tanggal WIB
import/raw/            file sumber utuh; subfolder unik per percobaan
import/parsed/         sel sebelum normalisasi + pemetaan sheet
import/ready/          record hasil normalisasi
snapshot/              20 snapshot terbaru, yang tertua dirotasi
export/auto/           Excel saat pindah RT/RW
export/manual/         hasil ekspor pengguna
recovered/             database lama dan laporan baris jurnal rusak
```

Folder tidak terenkripsi. Lindungi HP dengan kunci layar dan cadangkan lewat USB ke media aman. Berkas publik tetap ada setelah uninstall; jangan membagikan seluruh folder ke penerima yang tidak berwenang. Aplikasi tidak meminta INTERNET, tidak menyimpan foto KK, dan menonaktifkan Android auto-backup. Aplikasi lain yang dipilih pada dialog bagikan dapat mengunggah berkas atas tindakan pengguna.

Workbook pribadi di `data-exel/` diabaikan Git dan tidak dibundel ke APK. Impor membutuhkan file di perangkat. Tes workbook asli berjalan bila file tersedia lokal; tes sintetis tetap berjalan tanpa data pribadi.

## Ketahanan dan keputusan implementasi

- Satu penulis terserialisasi, satu transaksi SQLite per aksi. Event lengkap (termasuk null) di-flush ke JSONL sebelum SQLite; impor mencatat seluruh record dalam satu event agar data lama juga dapat dipulihkan.
- Startup memutar ulang event jurnal yang belum ada di database. Jika database hilang, ia dibangun ulang. Pemulihan eksplisit membangun kandidat terlebih dulu dan memindahkan DB lama beserta sidecar WAL/SHM ke `recovered`.
- Baris JSONL rusak dilaporkan dan dilewati. Pemulihan tidak dapat mengembalikan informasi yang hilang dari jurnal rusak; periksa laporan sebelum melanjutkan pendataan.
- Spec NIK bertentangan di satu paragraf; implementasi mengikuti kriteria terima: panjang/nonangka memblokir, peringatan lainnya tidak.
- Normalisasi `ABDURROHMAN` mengikuti algoritme: `abdurohman`, bukan typo contoh `aburohman`. Penggabungan huruf menggunakan `replaceAllMapped`, karena Dart tidak mengekspansi `$1` pada `replaceAll`.
- `excel` 4.x tidak menangani worksheet relationship absolut dan inline-string kosong dari openpyxl. Salinan parsing di memori dinormalkan; byte sumber tetap utuh di arsip.
- Data lama dilindungi trigger SQLite dari UPDATE/DELETE. Satu data lama tidak boleh ditautkan ke dua survei. NIK tidak memiliki unique constraint.
- Pending mencakup seluruh data lama belum tertaut, termasuk tanda abu-abu manual; tanda hanya mempengaruhi penghitung sisa. Konflik yang sudah tertaut bukan pending.
- Audit duplikat dan konflik mencakup seluruh database, meskipun ekspor DPS dibatasi RT/RW.

## Pengujian

Tes meliputi normalisasi, fuzzy matching, tanggal DD-first, NIK, impor workbook 504 baris, imutabilitas, duplikat, konflik, unlink/relink, replay identik, baris jurnal terpotong, database hilang, kegagalan penulisan jurnal, urutan/tipe sel Excel, snapshot dan perubahan sesi. Lakukan uji singkat izin, impor, simpan, ekspor, dan pemulihan di HP sasaran sebelum dipakai di lapangan.
