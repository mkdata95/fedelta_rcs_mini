import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final appDir = await getApplicationDocumentsDirectory();
    final databasesPath = join(appDir.path, 'database');
    final path = join(databasesPath, 'remote_control.db');
    print('데이터베이스 경로: $path');
    
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }
  
  Future<void> _onCreate(Database db, int version) async {
    // 장치 테이블 생성
    await db.execute('''
      CREATE TABLE devices (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        ip TEXT NOT NULL,
        status TEXT,
        network_status TEXT,
        extra TEXT
      )
    ''');
    
    // 프로젝터 스케줄 테이블 생성
    await db.execute('''
      CREATE TABLE projector_schedule (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        power_on_time TEXT NOT NULL,
        power_off_time TEXT NOT NULL,
        days TEXT NOT NULL,
        is_active INTEGER DEFAULT 1
      )
    ''');
    
    // 기본 스케줄 설정 초기화 (선택 사항)
    await db.insert('projector_schedule', {
      'power_on_time': '08:00',
      'power_off_time': '18:00',
      'days': '1,2,3,4,5', // 월-금
      'is_active': 1
    });
  }
  
  // 프로젝터 스케줄 저장
  Future<int> saveProjectorSchedule(Map<String, dynamic> schedule) async {
    final db = await database;
    
    // 기존 데이터가 있는지 확인
    final List<Map<String, dynamic>> existingSchedules = await db.query('projector_schedule');
    
    if (existingSchedules.isEmpty) {
      // 새 스케줄 추가
      return await db.insert('projector_schedule', schedule);
    } else {
      // 기존 스케줄 업데이트
      return await db.update(
        'projector_schedule', 
        schedule,
        where: 'id = ?',
        whereArgs: [existingSchedules.first['id']]
      );
    }
  }
  
  // 프로젝터 스케줄 로드
  Future<Map<String, dynamic>?> getProjectorSchedule() async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query('projector_schedule');
    
    if (result.isEmpty) {
      return null;
    }
    
    return result.first;
  }
  
  // 프로젝터 스케줄 활성화/비활성화
  Future<int> toggleProjectorSchedule(bool isActive) async {
    final db = await database;
    
    // 기존 데이터가 있는지 확인
    final List<Map<String, dynamic>> existingSchedules = await db.query('projector_schedule');
    
    if (existingSchedules.isEmpty) {
      // 데이터가 없으면 기본값으로 생성
      return await db.insert('projector_schedule', {
        'power_on_time': '08:00',
        'power_off_time': '18:00',
        'days': '1,2,3,4,5',
        'is_active': isActive ? 1 : 0
      });
    } else {
      // 기존 데이터 업데이트
      return await db.update(
        'projector_schedule', 
        {'is_active': isActive ? 1 : 0},
        where: 'id = ?',
        whereArgs: [existingSchedules.first['id']]
      );
    }
  }
} 