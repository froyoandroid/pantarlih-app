const schemaVersion = 4;
const schemaBaseVersion = 2;
const appVersion = '1.0.0+1';

const dropStatements = <String>[
  'DROP VIEW IF EXISTS v_duplikat_nama',
  'DROP VIEW IF EXISTS v_duplikat_nik',
  'DROP VIEW IF EXISTS v_konflik_rt',
  'DROP VIEW IF EXISTS v_sisa',
  'DROP TABLE IF EXISTS tanda_lama',
  'DROP TABLE IF EXISTS survei',
  'DROP TABLE IF EXISTS warga_lama',
  'DROP TABLE IF EXISTS warga',
  'DROP TABLE IF EXISTS referensi',
  'DROP TABLE IF EXISTS log',
  'DROP TABLE IF EXISTS urutan_id',
  'DROP TABLE IF EXISTS setelan',
];

const schemaStatements = <String>[
  '''CREATE TABLE referensi (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    urut_asli INTEGER,
    nama TEXT NOT NULL,
    nama_norm TEXT NOT NULL,
    nik_lama TEXT,
    jenis_kelamin TEXT,
    tempat_lahir TEXT,
    tgl_lahir TEXT,
    tgl_lahir_raw TEXT,
    desa TEXT,
    rt INTEGER,
    rw INTEGER,
    sumber_file TEXT,
    sumber_baris INTEGER,
    diimpor_pada TEXT NOT NULL
  )''',
  'CREATE INDEX idx_ref_norm ON referensi(nama_norm)',
  'CREATE INDEX idx_ref_rt ON referensi(rw, rt)',
  'CREATE INDEX idx_ref_tgl ON referensi(tgl_lahir)',
  '''CREATE TABLE warga (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    urut_sort INTEGER NOT NULL,
    grup_id INTEGER,
    nik TEXT,
    nama TEXT NOT NULL,
    nama_norm TEXT NOT NULL,
    jenis_kelamin TEXT CHECK (jenis_kelamin IN ('L','P')),
    tempat_lahir TEXT,
    tgl_lahir TEXT,
    desa TEXT,
    rt INTEGER NOT NULL,
    rw INTEGER NOT NULL,
    keterangan TEXT,
    sumber_input TEXT NOT NULL DEFAULT 'LAPANGAN'
      CHECK (sumber_input IN ('LAPANGAN','KERTAS')),
    dibuat_pada TEXT NOT NULL,
    diubah_pada TEXT NOT NULL
  )''',
  'CREATE UNIQUE INDEX idx_warga_urut ON warga(rw, rt, urut_sort)',
  'CREATE INDEX idx_warga_rt ON warga(rw, rt)',
  'CREATE INDEX idx_warga_nik ON warga(nik)',
  'CREATE INDEX idx_warga_norm ON warga(nama_norm)',
  'CREATE INDEX idx_warga_waktu ON warga(dibuat_pada)',
  '''CREATE TABLE log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL,
    op TEXT NOT NULL,
    tabel TEXT NOT NULL,
    row_id INTEGER,
    payload TEXT NOT NULL,
    schema_v INTEGER NOT NULL
  )''',
  'CREATE TABLE setelan (kunci TEXT PRIMARY KEY, nilai TEXT)',
  '''CREATE VIEW v_duplikat_nik AS
    SELECT nik, COUNT(*) AS jumlah
    FROM warga
    WHERE nik IS NOT NULL AND nik <> ''
    GROUP BY nik HAVING COUNT(*) > 1''',
  '''CREATE VIEW v_duplikat_nama AS
    SELECT nama_norm, rw, rt, COUNT(*) AS jumlah
    FROM warga
    GROUP BY nama_norm, rw, rt HAVING COUNT(*) > 1''',
];

const wargaColumns = <String>[
  'id',
  'urut_sort',
  'grup_id',
  'nik',
  'nama',
  'nama_norm',
  'jenis_kelamin',
  'tempat_lahir',
  'tgl_lahir',
  'desa',
  'kode_wilayah',
  'rt',
  'rw',
  'keterangan',
  'sumber_input',
  'dibuat_pada',
  'diubah_pada',
];

const referensiColumns = <String>[
  'id',
  'urut_asli',
  'nama',
  'nama_norm',
  'nik_lama',
  'jenis_kelamin',
  'tempat_lahir',
  'tgl_lahir',
  'tgl_lahir_raw',
  'desa',
  'rt',
  'rw',
  'kode_wilayah',
  'sumber_file',
  'sumber_baris',
  'diimpor_pada',
];

const lokasiColumns = <String>[
  'kode',
  'nama_desa',
  'nama_kec',
  'nama_kab',
  'nama_prov',
  'kode_kec',
  'nik_prefix',
  'sumber_versi',
  'manual',
  'dicatat_pada',
];
