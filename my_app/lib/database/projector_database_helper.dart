import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class ProjectorDatabaseHelper {
  static final ProjectorDatabaseHelper _instance = ProjectorDatabaseHelper._internal();
  static Database? _database;

  factory ProjectorDatabaseHelper() => _instance;

  ProjectorDatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = 'my_app/database';
    final path = join(databasesPath, 'projector_control.db');

    print('프로젝터 데이터베이스 초기화: $path');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 프로젝터 테이블 생성
    await db.execute('''
      CREATE TABLE projectors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL,
        name TEXT NOT NULL,
        ip TEXT NOT NULL,
        port INTEGER NOT NULL DEFAULT 80,
        model TEXT NOT NULL,
        username TEXT NOT NULL DEFAULT 'admin',
        password TEXT NOT NULL DEFAULT 'admin',
        status TEXT DEFAULT 'offline',
        power_status TEXT DEFAULT 'offline',
        network_status TEXT DEFAULT 'unknown',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // 프로젝터 로그 테이블 생성
    await db.execute('''
      CREATE TABLE projector_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        projector_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        result TEXT NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (projector_id) REFERENCES projectors (id) ON DELETE CASCADE
      )
    ''');

    // 프로젝터 스케줄 테이블 생성
    await db.execute('''
      CREATE TABLE projector_schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        projector_id INTEGER NOT NULL,
        power_on_time TEXT NOT NULL,
        power_off_time TEXT NOT NULL,
        days TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (projector_id) REFERENCES projectors (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('프로젝터 데이터베이스 업그레이드: $oldVersion -> $newVersion');
    
    if (oldVersion < 1) {
      await _onCreate(db, newVersion);
    }
  }
} 