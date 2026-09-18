# Data Wilayah Kemendagri

Dokumen ini mendeskripsikan keadaan sekarang: bentuk data sumber, skema pack, cara aplikasi membukanya, dan cara membangun ulang. Riwayat pengerjaan (daftar tugas W1–W11) sudah dihapus karena pekerjaan itu selesai.

Sumber: [cahyadsn/wilayah](https://github.com/cahyadsn/wilayah) oleh Cahya DSN, lisensi MIT. Pack yang dibundel mengikuti Kepmendagri No. 300.2.2-2430 Tahun 2025. Teks lisensi sumber ada di `third_party/wilayah/LICENSE`, SHA dan tanggal unduh di `third_party/wilayah/SOURCE.txt`.

Isi pack penuh: 91.599 baris (38 provinsi, 514 kabupaten/kota, 7.285 kecamatan, 83.762 desa/kelurahan).

## Bentuk data sumber

Upstream menerbitkan satu tabel SQL: `wilayah (kode, nama)`. Kode bertitik dan hierarkis, panjang menentukan level: 2 digit provinsi, 5 kabupaten/kota, 8 kecamatan, 13 desa/kelurahan. Induk adalah potongan sebelum titik terakhir. Berkas `db/wilayah.sql` hanya diparse saat build, tidak di runtime.

## Skema pack

`tool/build_wilayah.dart` mengubah dump menjadi `assets/wilayah.db` dengan dua tabel:

```text
wilayah (kode TEXT PK, nama, level INTEGER, induk, nama_norm, kode_polos)
wilayah_meta (kunci TEXT PK, nilai)
```

`nama_norm` adalah hasil normalisasi untuk pencarian fuzzy, `kode_polos` adalah kode tanpa titik. `wilayah_meta` memuat kepmendagri, sha_sumber, dibuat_pada, jumlah per level, dan filter_prov bila pack difilter. Indeks ada pada `(induk, nama)`, `nama_norm`, dan `(level, nama)`.

Angka jumlah di `tool/build_wilayah.dart` (`expectedCounts`) adalah gerbang build: bila dump dan angka tidak cocok, skrip gagal daripada menghasilkan aset setengah jadi.

## Cara aplikasi membukanya

`WilayahRepo` (`lib/data/wilayah.dart`) menyalin aset ke direktori support privat dengan nama memuat SHA pendek (`wilayah_<12 digit>.db`), lalu membukanya dengan `readOnly: true`. Pack baru tersalin otomatis tanpa logika versi tambahan.

Tiga sifat yang tidak boleh berubah:

- Data wilayah tidak pernah masuk jurnal JSONL. Yang dijurnal hanya pilihan pengguna (satu baris `lokasi`), bukan 91.600 baris referensi.
- Pack read-only dan tidak pernah ikut `rebuild()`.
- Gagal dibuka tidak menggagalkan startup. Repo berstatus unavailable, layar lokasi beralih ke mode ketik manual, dan pengguna tetap dapat menyimpan.

## Snapshot lokasi

Pilihan petugas tersimpan di tabel `lokasi` pada `pantarlih.db`: kode resmi plus snapshot nama desa, kecamatan, kabupaten, provinsi, kode kecamatan, prefix NIK, versi sumber, dan penanda manual. Setiap baris warga membawa salinan `kode_wilayah` dan `desa` tanpa foreign key.

**Memperbarui pack tidak pernah mengubah data yang sudah tersimpan.** Sheet INFO pada ekspor membaca snapshot itu, bukan `wilayah.db`.

## Membangun ulang pack

Di desktop, bukan di HP:

```sh
# unduh db/wilayah.sql terbaru ke third_party/wilayah/wilayah.sql
# perbarui SHA di third_party/wilayah/SOURCE.txt dan tool/build_wilayah.dart
dart run tool/build_wilayah.dart
```

Lalu build APK. Opsional: `dart run tool/build_wilayah.dart --prov=33` hanya memasukkan Jawa Tengah. Build penuh adalah bawaan.

## Keputusan desain

1. `wilayah.db` adalah database terpisah, bukan tabel di `pantarlih.db`.
2. `wilayah.sql` hanya diparse saat build, tidak di runtime.
3. Simpan kode (`warga.kode_wilayah`) dan snapshot nama (`warga.desa`, kolom nama di `lokasi`). Referensi tidak pernah jadi sumber kebenaran.
4. Enam digit pertama NIK adalah kecamatan penerbitan, bukan domisili. Peringatan kuning, bukan penghalang.
5. Tidak ada daftar RT/RW dari data Kemendagri. Kode resmi berhenti di desa/kelurahan.
