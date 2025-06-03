import 'dart:async';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

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
    // PC 전용 데이터베이스 경로 설정
    String path = join(await getDatabasesPath(), 'pc_control.db');
    print('PC 데이터베이스 경로: $path');
    
    // 데이터베이스 존재 여부 확인
    bool exists = await databaseExists(path);
    print('PC 데이터베이스 존재 여부: $exists');
    
    print('PC 데이터베이스 열기 시작');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        print('새 PC 데이터베이스 생성: 테이블 생성 시작');
        await _onCreate(db, version);
        print('PC 테이블 생성 완료');
      },
      onOpen: (db) {
        print('기존 PC 데이터베이스 열기 성공');
      }
    );
    
    // 테이블 생성 확인
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    print('PC 데이터베이스 테이블 목록: $tables');
    
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    // PC 테이블 생성
    await db.execute('''
      CREATE TABLE pcs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL,
        name TEXT NOT NULL,
        ip TEXT NOT NULL,
        mac TEXT NOT NULL,
        status TEXT DEFAULT 'offline',
        network_status TEXT DEFAULT 'unknown',
        os_type TEXT DEFAULT 'windows',
        group_name TEXT,
        location TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // PC 로그 테이블 생성
    await db.execute('''
      CREATE TABLE pc_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pc_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        result TEXT NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (pc_id) REFERENCES pcs (id) ON DELETE CASCADE
      )
    ''');

    // PC 스케줄 테이블 생성 (단일 스케줄 방식으로 변경)
    await db.execute('''
      CREATE TABLE pc_schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        wake_on_time TEXT,
        shutdown_time TEXT,
        days TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    
    // PC 그룹 테이블 생성
    await db.execute('''
      CREATE TABLE pc_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    
    // PC 그룹 매핑 테이블 생성
    await db.execute('''
      CREATE TABLE pc_group_mappings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pc_id INTEGER NOT NULL,
        group_id INTEGER NOT NULL,
        FOREIGN KEY (pc_id) REFERENCES pcs (id) ON DELETE CASCADE,
        FOREIGN KEY (group_id) REFERENCES pc_groups (id) ON DELETE CASCADE
      )
    ''');
  }

  // UUID 생성 메서드
  String generateUUID() {
    return _uuid.v4();
  }

  // PC 관련 CRUD 메서드
  Future<int> insertPC(Map<String, dynamic> pc) async {
    final db = await database;
    
    // UUID가 없으면 자동으로 할당
    if (!pc.containsKey('uuid') || pc['uuid'] == null || pc['uuid'].toString().isEmpty) {
      pc['uuid'] = generateUUID();
    }
    
    return await db.insert(
      'pcs',
      pc,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllPCs() async {
    final db = await database;
    return await db.query('pcs');
  }
  
  Future<List<Map<String, dynamic>>> getPCsByGroup(int groupId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT p.* FROM pcs p
      JOIN pc_group_mappings m ON p.id = m.pc_id
      WHERE m.group_id = ?
    ''', [groupId]);
  }

  Future<Map<String, dynamic>?> getPCById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'pcs',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return result.first;
  }

  Future<Map<String, dynamic>?> getPCByUUID(String uuid) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'pcs',
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
    if (result.isEmpty) return null;
    return result.first;
  }

  Future<Map<String, dynamic>?> getPCByIP(String ip) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'pcs',
      where: 'ip = ?',
      whereArgs: [ip],
    );
    if (result.isEmpty) return null;
    return result.first;
  }
  
  Future<Map<String, dynamic>?> getPCByMAC(String mac) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'pcs',
      where: 'mac = ?',
      whereArgs: [mac],
    );
    if (result.isEmpty) return null;
    return result.first;
  }

  Future<int> updatePC(Map<String, dynamic> pc) async {
    final db = await database;
    if (pc.containsKey('uuid') && pc['uuid'] != null) {
      // UUID로 업데이트
      return await db.update(
        'pcs',
        pc,
        where: 'uuid = ?',
        whereArgs: [pc['uuid']],
      );
    } else {
      // ID로 업데이트
      return await db.update(
        'pcs',
        pc,
        where: 'id = ?',
        whereArgs: [pc['id']],
      );
    }
  }

  Future<int> deletePCById(int id) async {
    final db = await database;
    return await db.delete(
      'pcs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deletePCByUUID(String uuid) async {
    final db = await database;
    return await db.delete(
      'pcs',
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<int> updatePCStatus(int id, String status) async {
    final db = await database;
    return await db.update(
      'pcs',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updatePCStatusByUUID(String uuid, String status) async {
    final db = await database;
    return await db.update(
      'pcs',
      {'status': status},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }
  
  Future<int> updatePCNetworkStatus(int id, String networkStatus) async {
    final db = await database;
    return await db.update(
      'pcs',
      {'network_status': networkStatus},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // PC 로그 관련 메서드
  Future<int> insertPCLog(Map<String, dynamic> log) async {
    final db = await database;
    
    // 날짜 필드 이름 변경 (created_at -> timestamp)
    if (log.containsKey('created_at')) {
      log['timestamp'] = log['created_at'];
      log.remove('created_at');
    } else {
      log['timestamp'] = DateTime.now().toIso8601String();
    }
    
    return await db.insert(
      'pc_logs',
      log,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPCLogs(int pcId, {int limit = 20}) async {
    final db = await database;
    return await db.query(
      'pc_logs',
      where: 'pc_id = ?',
      whereArgs: [pcId],
      orderBy: 'timestamp DESC',
      limit: limit
    );
  }

  // PC 상태 변경 마지막 로그 가져오기
  Future<Map<String, dynamic>?> getLastStatusLog(int pcId) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.query(
      'pc_logs',
      where: 'pc_id = ? AND action IN (?, ?, ?, ?, ?)',
      whereArgs: [pcId, 'wake', 'shutdown', 'reboot', 'status_change', 'auto_status_change'],
      orderBy: 'timestamp DESC',
      limit: 1
    );
    
    if (results.isNotEmpty) {
      return results.first;
    }
    
    // 로그가 없는 경우 null 반환
    return null;
  }

  // PC 스케줄 관련 메서드
  Future<int> insertPCSchedule(Map<String, dynamic> schedule) async {
    final db = await database;
    return await db.insert(
      'pc_schedules',
      schedule,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  // PC 스케줄 삭제 (단일 스케줄만 유지하기 위해 전체 삭제)
  Future<int> deleteAllPCSchedules() async {
    final db = await database;
    return await db.delete('pc_schedules');
  }

  // PC 스케줄 가져오기 (전체 - 단일 스케줄만 조회)
  Future<List<Map<String, dynamic>>> getPCSchedule() async {
    final db = await database;
    return await db.query('pc_schedules', limit: 1);
  }
  
  // PC 스케줄 활성화/비활성화
  Future<int> updatePCScheduleStatus(int id, bool isActive) async {
    final db = await database;
    return await db.update(
      'pc_schedules',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // PC 그룹 관련 메서드
  Future<int> insertPCGroup(Map<String, dynamic> group) async {
    final db = await database;
    return await db.insert('pc_groups', group);
  }
  
  Future<List<Map<String, dynamic>>> getAllPCGroups() async {
    final db = await database;
    return await db.query('pc_groups');
  }
  
  Future<int> updatePCGroup(Map<String, dynamic> group) async {
    final db = await database;
    return await db.update(
      'pc_groups',
      group,
      where: 'id = ?',
      whereArgs: [group['id']],
    );
  }
  
  Future<int> deletePCGroup(int id) async {
    final db = await database;
    return await db.delete(
      'pc_groups',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  // PC 그룹 매핑 메서드
  Future<int> addPCToGroup(int pcId, int groupId) async {
    final db = await database;
    return await db.insert(
      'pc_group_mappings',
      {'pc_id': pcId, 'group_id': groupId}
    );
  }
  
  Future<int> removePCFromGroup(int pcId, int groupId) async {
    final db = await database;
    return await db.delete(
      'pc_group_mappings',
      where: 'pc_id = ? AND group_id = ?',
      whereArgs: [pcId, groupId],
    );
  }
  
  Future<int> removeAllPCsFromGroup(int groupId) async {
    final db = await database;
    return await db.delete(
      'pc_group_mappings',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
  }

  // 데이터베이스 초기화 (테스트용)
  Future<void> resetDatabase() async {
    final db = await database;
    await db.execute('DROP TABLE IF EXISTS pc_group_mappings');
    await db.execute('DROP TABLE IF EXISTS pc_groups');
    await db.execute('DROP TABLE IF EXISTS pc_logs');
    await db.execute('DROP TABLE IF EXISTS pc_schedules');
    await db.execute('DROP TABLE IF EXISTS pcs');
    await _onCreate(db, 1);
  }
} 