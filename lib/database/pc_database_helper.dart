import 'dart:async';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';

class PCDatabaseHelper {
  static final PCDatabaseHelper _instance = PCDatabaseHelper._internal();
  static Database? _database;
  final Uuid _uuid = Uuid();

  factory PCDatabaseHelper() => _instance;

  PCDatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final appDir = await getApplicationDocumentsDirectory();
    final databasesPath = join(appDir.path, 'database');
    final path = join(databasesPath, 'pc_control.db');
    print('PC 데이터베이스 경로: $path');
    
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }
  
  Future<void> _onCreate(Database db, int version) async {
    // PC 장치 테이블 생성
    await db.execute('''
      CREATE TABLE pc_devices (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        ip TEXT NOT NULL,
        mac_address TEXT,
        status TEXT,
        network_status TEXT,
        extra TEXT
      )
    ''');
    
    // PC 스케줄 테이블 생성
    await db.execute('''
      CREATE TABLE pc_schedule (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        days TEXT NOT NULL,
        is_active INTEGER DEFAULT 1
      )
    ''');
    
    // PC 그룹 테이블 생성
    await db.execute('''
      CREATE TABLE pc_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT
      )
    ''');
    
    // PC-그룹 관계 테이블 생성
    await db.execute('''
      CREATE TABLE pc_group_relation (
        pc_id TEXT,
        group_id TEXT,
        PRIMARY KEY (pc_id, group_id),
        FOREIGN KEY (pc_id) REFERENCES pc_devices (id) ON DELETE CASCADE,
        FOREIGN KEY (group_id) REFERENCES pc_groups (id) ON DELETE CASCADE
      )
    ''');
    
    // 기본 스케줄 설정 초기화
    await db.insert('pc_schedule', {
      'start_time': '08:00',
      'end_time': '18:00',
      'days': '1,2,3,4,5', // 월-금
      'is_active': 1
    });
  }
  
  // PC 추가
  Future<String> addPC(Map<String, dynamic> pc) async {
    final db = await database;
    final id = _uuid.v4(); // UUID 생성
    pc['id'] = id;
    
    await db.insert('pc_devices', pc);
    return id;
  }
  
  // PC 목록 가져오기
  Future<List<Map<String, dynamic>>> getPCs() async {
    final db = await database;
    return await db.query('pc_devices');
  }
  
  // PC 정보 업데이트
  Future<int> updatePC(Map<String, dynamic> pc) async {
    final db = await database;
    return await db.update(
      'pc_devices',
      pc,
      where: 'id = ?',
      whereArgs: [pc['id']]
    );
  }
  
  // PC 삭제
  Future<int> deletePC(String id) async {
    final db = await database;
    return await db.delete(
      'pc_devices',
      where: 'id = ?',
      whereArgs: [id]
    );
  }
  
  // PC 스케줄 저장
  Future<int> savePCSchedule(Map<String, dynamic> schedule) async {
    final db = await database;
    
    // 기존 데이터가 있는지 확인
    final List<Map<String, dynamic>> existingSchedules = await db.query('pc_schedule');
    
    if (existingSchedules.isEmpty) {
      // 새 스케줄 추가
      return await db.insert('pc_schedule', schedule);
    } else {
      // 기존 스케줄 업데이트
      return await db.update(
        'pc_schedule', 
        schedule,
        where: 'id = ?',
        whereArgs: [existingSchedules.first['id']]
      );
    }
  }
  
  // PC 스케줄 로드
  Future<Map<String, dynamic>?> getPCSchedule() async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query('pc_schedule');
    
    if (result.isEmpty) {
      return null;
    }
    
    return result.first;
  }
  
  // PC 스케줄 활성화/비활성화
  Future<int> togglePCSchedule(bool isActive) async {
    final db = await database;
    
    // 기존 데이터가 있는지 확인
    final List<Map<String, dynamic>> existingSchedules = await db.query('pc_schedule');
    
    if (existingSchedules.isEmpty) {
      // 데이터가 없으면 기본값으로 생성
      return await db.insert('pc_schedule', {
        'start_time': '08:00',
        'end_time': '18:00',
        'days': '1,2,3,4,5',
        'is_active': isActive ? 1 : 0
      });
    } else {
      // 기존 데이터 업데이트
      return await db.update(
        'pc_schedule', 
        {'is_active': isActive ? 1 : 0},
        where: 'id = ?',
        whereArgs: [existingSchedules.first['id']]
      );
    }
  }
  
  // PC 그룹 추가
  Future<String> addPCGroup(String name, {String? description}) async {
    final db = await database;
    final id = _uuid.v4(); // UUID 생성
    
    await db.insert('pc_groups', {
      'id': id,
      'name': name,
      'description': description
    });
    
    return id;
  }
  
  // PC를 그룹에 추가
  Future<void> addPCToGroup(String pcId, String groupId) async {
    final db = await database;
    await db.insert('pc_group_relation', {
      'pc_id': pcId,
      'group_id': groupId
    });
  }
  
  // PC 그룹 목록 가져오기
  Future<List<Map<String, dynamic>>> getPCGroups() async {
    final db = await database;
    return await db.query('pc_groups');
  }
  
  // 그룹에 속한 PC 목록 가져오기
  Future<List<Map<String, dynamic>>> getPCsInGroup(String groupId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT p.* FROM pc_devices p
      JOIN pc_group_relation r ON p.id = r.pc_id
      WHERE r.group_id = ?
    ''', [groupId]);
  }
} 