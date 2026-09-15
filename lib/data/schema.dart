const schemaVersion = 1;

const schemaStatements = <String>[
  '''CREATE TABLE warga_lama (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    urut_asli INTEGER NOT NULL, urut_sort INTEGER NOT NULL,
    nama TEXT NOT NULL, nama_norm TEXT NOT NULL, nama_tokens TEXT NOT NULL,
    nik_lama TEXT, nik_prefix TEXT,
    jenis_kelamin TEXT CHECK(jenis_kelamin IN ('L','P')),
    tempat_lahir TEXT, tgl_lahir TEXT, tgl_lahir_raw TEXT, desa TEXT,
    rt INTEGER NOT NULL, rw INTEGER NOT NULL,
    perlu_review INTEGER NOT NULL DEFAULT 0,
    sumber_file TEXT, sumber_baris INTEGER, diimpor_pada TEXT NOT NULL,
    UNIQUE(rt, urut_asli)
  )''',
  'CREATE INDEX idx_lama_norm ON warga_lama(nama_norm)',
  'CREATE INDEX idx_lama_rt ON warga_lama(rw, rt)',
  'CREATE INDEX idx_lama_tgl ON warga_lama(tgl_lahir)',
  '''CREATE TRIGGER immutable_lama_update BEFORE UPDATE ON warga_lama
    BEGIN SELECT RAISE(ABORT, 'Data lama tidak dapat diubah'); END''',
  '''CREATE TRIGGER immutable_lama_delete BEFORE DELETE ON warga_lama
    BEGIN SELECT RAISE(ABORT, 'Data lama tidak dapat dihapus'); END''',
  '''CREATE TABLE tanda_lama (
    id_lama INTEGER PRIMARY KEY REFERENCES warga_lama(id),
    abu_abu INTEGER NOT NULL DEFAULT 0, ditandai_pada TEXT NOT NULL
  )''',
  '''CREATE TABLE survei (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    id_lama INTEGER REFERENCES warga_lama(id), grup_id INTEGER,
    nik TEXT, nama TEXT NOT NULL, nama_norm TEXT NOT NULL,
    jenis_kelamin TEXT CHECK(jenis_kelamin IN ('L','P')),
    tempat_lahir TEXT, tgl_lahir TEXT, desa TEXT,
    rt_lama INTEGER, rw_lama INTEGER, rt_baru INTEGER NOT NULL, rw_baru INTEGER NOT NULL,
    keterangan TEXT,
    sumber_input TEXT NOT NULL CHECK(sumber_input IN ('LAPANGAN','KERTAS')),
    dibuat_pada TEXT NOT NULL, diubah_pada TEXT NOT NULL
  )''',
  'CREATE INDEX idx_survei_lama ON survei(id_lama)',
  'CREATE INDEX idx_survei_rt ON survei(rw_baru, rt_baru)',
  'CREATE INDEX idx_survei_nik ON survei(nik)',
  'CREATE INDEX idx_survei_waktu ON survei(dibuat_pada)',
  '''CREATE TABLE log (
    id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT NOT NULL, op TEXT NOT NULL,
    tabel TEXT NOT NULL, row_id INTEGER, payload TEXT NOT NULL, schema_v INTEGER NOT NULL
  )''',
  'CREATE TABLE setelan (kunci TEXT PRIMARY KEY, nilai TEXT)',
  '''CREATE VIEW v_konflik_rt AS SELECT s.*, w.nama AS nama_lama
    FROM survei s JOIN warga_lama w ON w.id = s.id_lama
    WHERE s.id_lama IS NOT NULL AND
      (s.rt_baru <> s.rt_lama OR s.rw_baru <> s.rw_lama)''',
  '''CREATE VIEW v_sisa AS
    SELECT w.id, w.urut_asli, w.nama, w.tgl_lahir, w.tgl_lahir_raw,
      w.jenis_kelamin, w.rt, w.rw, COALESCE(t.abu_abu, 0) AS abu_abu
    FROM warga_lama w LEFT JOIN tanda_lama t ON t.id_lama = w.id
    WHERE NOT EXISTS(SELECT 1 FROM survei s WHERE s.id_lama = w.id)''',
  '''CREATE VIEW v_duplikat_nik AS SELECT nik, COUNT(*) AS jumlah FROM survei
    WHERE nik IS NOT NULL AND nik <> '' GROUP BY nik HAVING COUNT(*) > 1''',
];
