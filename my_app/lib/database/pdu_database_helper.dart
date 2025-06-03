import 'dart:async';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';

class PDUDatabaseHelper {
  static final PDUDatabaseHelper _instance = PDUDatabaseHelper._internal();
  static Database? _database;
  final Uuid _uuid = Uuid();

  factory PDUDatabaseHelper() => _instance;

  PDUDatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // 데이터베이스 강제 재연결 메서드
  Future<Database> forceReconnect() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final appDir = await getApplicationDocumentsDirectory();
    final databasesPath = join(appDir.path, 'database');
    final path = join(databasesPath, 'pdu_control.db');

    print('PDU 데이터베이스 초기화: $path');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      readOnly: false,
    );
  }

  Future<void> _migrateV1ToV2(Database db) async {
    print('V1 -> V2 마이그레이션 시작: uuid 필드 추가');
    
    // uuid 필드 추가
    await db.execute('ALTER TABLE pdus ADD COLUMN uuid TEXT');
    
    // 기존 레코드에 uuid 할당
    final existingPdus = await db.query('pdus');
    for (var pdu in existingPdus) {
      final uuid = _uuid.v4();
      await db.update(
        'pdus',
        {'uuid': uuid},
        where: 'id = ?',
        whereArgs: [pdu['id']],
      );
      print('PDU ID ${pdu['id']}에 UUID $uuid 할당됨');
    }
    
    print('V1 -> V2 마이그레이션 완료');
  }

  Future<void> _migrateV2ToV3(Database db) async {
    print('V2 -> V3 마이그레이션 시작: power_status 필드 추가');
    
    // power_status 필드 추가
    await db.execute('ALTER TABLE pdus ADD COLUMN power_status TEXT');
    
    // 기존 레코드에 status 값을 power_status로 복사
    final existingPdus = await db.query('pdus');
    for (var pdu in existingPdus) {
      final status = pdu['status'] ?? 'offline';
      await db.update(
        'pdus',
        {'power_status': status},
        where: 'id = ?',
        whereArgs: [pdu['id']],
      );
      print('PDU ID ${pdu['id']}의 status($status)가 power_status로 복사됨');
    }
    
    print('V2 -> V3 마이그레이션 완료');
  }

  Future<void> _onCreate(Database db, int version) async {
    // PDU 테이블 생성 (uuid 필드와 power_status 필드 포함)
    await db.execute('''
      CREATE TABLE pdus (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL,
        name TEXT NOT NULL,
        ip TEXT NOT NULL,
        port INTEGER NOT NULL DEFAULT 80,
        model TEXT NOT NULL,
        username TEXT NOT NULL DEFAULT 'administrator',
        password TEXT NOT NULL DEFAULT 'password',
        status TEXT DEFAULT 'offline',
        power_status TEXT DEFAULT 'offline',
        network_status TEXT DEFAULT 'unknown',
        outlet_count INTEGER DEFAULT 8,
        outlets TEXT DEFAULT '{}',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // PDU 로그 테이블 생성
    await db.execute('''
      CREATE TABLE pdu_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pdu_id INTEGER NOT NULL,
        outlet_id INTEGER DEFAULT 0,
        action TEXT NOT NULL,
        result TEXT NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (pdu_id) REFERENCES pdus (id) ON DELETE CASCADE
      )
    ''');

    // PDU 스케줄 테이블 생성 (단일 스케줄 방식으로 변경)
    await db.execute('''
      CREATE TABLE pdu_schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pdu_id TEXT NOT NULL,
        power_on_time TEXT,
        power_off_time TEXT,
        days TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('PDU 데이터베이스 업그레이드: $oldVersion -> $newVersion');
    if (oldVersion < 2) {
      // 버전 1에서 2로 마이그레이션: uuid 필드 추가
      await _migrateV1ToV2(db);
    }
    if (oldVersion < 3) {
      // 버전 2에서 3으로 마이그레이션: power_status 필드 추가
      await _migrateV2ToV3(db);
    }
  }

  // UUID 생성 메서드
  String generateUUID() {
    return _uuid.v4();
  }

  // PDU 관련 CRUD 메서드
  Future<int> insertPDU(Map<String, dynamic> pdu) async {
    final db = await database;
    
    // UUID가 없으면 자동으로 할당
    if (!pdu.containsKey('uuid') || pdu['uuid'] == null || pdu['uuid'].toString().isEmpty) {
      pdu['uuid'] = generateUUID();
    }
    
    return await db.insert(
      'pdus',
      pdu,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllPDUs() async {
    final db = await database;
    return await db.query('pdus');
  }

  Future<Map<String, dynamic>?> getPDUById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'pdus',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return result.first;
  }

  Future<Map<String, dynamic>?> getPDUByUUID(String uuid) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'pdus',
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
    if (result.isEmpty) return null;
    return result.first;
  }

  Future<Map<String, dynamic>?> getPDUByIpAndPort(String ip, int port) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'pdus',
      where: 'ip = ? AND port = ?',
      whereArgs: [ip, port],
    );
    if (result.isEmpty) return null;
    return result.first;
  }

  Future<Map<String, dynamic>?> getPDUByIp(String ip) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'pdus',
      where: 'ip = ?',
      whereArgs: [ip],
    );
    if (result.isEmpty) return null;
    return result.first;
  }

  Future<int> updatePDU(Map<String, dynamic> pdu) async {
    final db = await database;
    if (pdu.containsKey('uuid') && pdu['uuid'] != null) {
      // UUID로 업데이트
      return await db.update(
        'pdus',
        pdu,
        where: 'uuid = ?',
        whereArgs: [pdu['uuid']],
      );
    } else {
      // ID로 업데이트 (이전 방식)
      return await db.update(
        'pdus',
        pdu,
        where: 'id = ?',
        whereArgs: [pdu['id']],
      );
    }
  }

  Future<int> deletePDUById(int id) async {
    final db = await database;
    return await db.delete(
      'pdus',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deletePDUByUUID(String uuid) async {
    final db = await database;
    return await db.delete(
      'pdus',
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<int> updatePDUStatus(int id, String status) async {
    final db = await database;
    // status와 power_status 동시 업데이트
    return await db.update(
      'pdus',
      {
        'status': status,
        'power_status': status
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updatePDUStatusByUUID(String uuid, String status) async {
    final db = await database;
    // status와 power_status 동시 업데이트
    return await db.update(
      'pdus',
      {
        'status': status,
        'power_status': status
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  // power_status만 별도로 업데이트하는 함수
  Future<int> updatePDUPowerStatus(int id, String powerStatus) async {
    final db = await database;
    return await db.update(
      'pdus',
      {'power_status': powerStatus},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // UUID로 power_status 업데이트
  Future<int> updatePDUPowerStatusByUUID(String uuid, String powerStatus) async {
    final db = await database;
    return await db.update(
      'pdus',
      {'power_status': powerStatus},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  // PDU 포트 상태 업데이트
  Future<int> updatePDUOutlets(int id, String outletsJson) async {
    final db = await database;
    return await db.update(
      'pdus',
      {'outlets': outletsJson},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updatePDUOutletsByUUID(String uuid, String outletsJson) async {
    final db = await database;
    return await db.update(
      'pdus',
      {'outlets': outletsJson},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  // PDU 로그 관련 메서드
  Future<int> insertPDULog(Map<String, dynamic> log) async {
    final db = await database;
    return await db.insert('pdu_logs', log);
  }

  Future<List<Map<String, dynamic>>> getPDULogs(int pduId, {int limit = 50}) async {
    final db = await database;
    return await db.query(
      'pdu_logs',
      where: 'pdu_id = ?',
      whereArgs: [pduId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  // PDU 스케줄 관련 메서드
  Future<int> insertPDUSchedule(Map<String, dynamic> schedule) async {
    // 데이터베이스 연결 강제 재연결
    final db = await forceReconnect();
    try {
      return await db.insert('pdu_schedules', schedule);
    } catch (e) {
      print('PDU 스케줄 추가 중 오류: $e');
      throw e;
    }
  }
  
  // PDU 스케줄 삭제 (단일 스케줄만 유지하기 위해 전체 삭제)
  Future<int> deleteAllPDUSchedules() async {
    try {
      final db = await database;
      
      // 기존 방식은 읽기 전용 문제가 발생할 수 있음
      // return await db.delete('pdu_schedules');
      
      // 대신 테이블을 삭제하고 다시 생성
      await db.execute('DROP TABLE IF EXISTS pdu_schedules');
      
      // 테이블 다시 생성
      await db.execute('''
        CREATE TABLE pdu_schedules (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          pdu_id TEXT NOT NULL,
          power_on_time TEXT,
          power_off_time TEXT,
          days TEXT NOT NULL,
          is_active INTEGER DEFAULT 1,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      
      print('PDU 스케줄 테이블을 삭제하고 다시 생성했습니다.');
      return 1; // 성공 값 반환
    } catch (e) {
      print('PDU 스케줄 테이블 재생성 중 오류: $e');
      throw e;
    }
  }

  // PDU 스케줄 가져오기 (전체 - 단일 스케줄만 조회)
  Future<List<Map<String, dynamic>>> getPDUSchedule() async {
    final db = await database;
    return await db.query('pdu_schedules', limit: 1);
  }
  
  // PDU 스케줄 활성화/비활성화
  Future<int> updatePDUScheduleStatus(int id, bool isActive) async {
    final db = await database;
    return await db.update(
      'pdu_schedules',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 공통 PDU 스케줄 조회 메서드
  Future<List<Map<String, dynamic>>> getCommonPDUSchedules() async {
    final db = await database;
    print('[PDU-DB] 공통 스케줄 조회: pdu_schedules 테이블에서 스케줄 조회 시작');
    
    final schedules = await db.query('pdu_schedules');
    
    print('[PDU-DB] 공통 스케줄 조회 결과: ${schedules.length}개의 스케줄 찾음');
    if (schedules.isEmpty) {
      print('[PDU-DB] 등록된 공통 스케줄이 없습니다. 기본 공통 스케줄을 생성합니다.');
      
      // UUID 생성
      final uuid = generateUUID();
      
      // 기본 스케줄 생성
      final defaultSchedule = {
        'pdu_id': uuid, // UUID 사용
        'power_on_time': '09:00',
        'power_off_time': '18:00', 
        'days': '1,2,3,4,5',  // 월-금
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String()
      };
      
      final id = await insertPDUSchedule(defaultSchedule);
      print('[PDU-DB] 기본 공통 스케줄이 ID $id로 생성되었습니다.');
      
      // 새로 생성된 스케줄 반환
      return [
        {...defaultSchedule, 'id': id}
      ];
    }
    
    for (var schedule in schedules) {
      print('[PDU-DB] 공통 스케줄 정보: ID=${schedule['id']}, 켜기=${schedule['power_on_time']}, 끄기=${schedule['power_off_time']}, 요일=${schedule['days']}, 활성화=${schedule['is_active']}');
    }
    
    return schedules;
  }
  
  // 공통 PDU 스케줄 삭제 메서드
  Future<int> deleteCommonPDUSchedules() async {
    final db = await database;
    return await db.delete('pdu_schedules');
  }

  Future<int> updatePDUSchedule(Map<String, dynamic> schedule) async {
    // 데이터베이스 연결 강제 재연결
    final db = await forceReconnect();
    try {
      return await db.update(
        'pdu_schedules',
        schedule,
        where: 'id = ?',
        whereArgs: [schedule['id']],
      );
    } catch (e) {
      print('PDU 스케줄 업데이트 중 오류: $e');
      throw e;
    }
  }

  Future<int> deletePDUSchedule(int id) async {
    final db = await database;
    return await db.delete(
      'pdu_schedules',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 데이터베이스 초기화 (테스트용)
  Future<void> resetDatabase() async {
    final db = await database;
    await db.execute('DROP TABLE IF EXISTS pdu_logs');
    await db.execute('DROP TABLE IF EXISTS pdu_schedules');
    await db.execute('DROP TABLE IF EXISTS pdus');
    await _onCreate(db, 3); // 최신 버전으로 다시 생성
  }

  Future<int> updatePDUNetworkStatus(int id, String networkStatus) async {
    final db = await database;
    return await db.update(
      'pdus',
      {'network_status': networkStatus},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updatePDUNetworkStatusByUUID(String uuid, String networkStatus) async {
    final db = await database;
    return await db.update(
      'pdus',
      {'network_status': networkStatus},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  // 공통 스케줄 조회
  Future<Map<String, dynamic>> getCommonSchedule() async {
    final db = await database;
    
    // 공통 스케줄 조회 (첫 번째 스케줄을 반환)
    final List<Map<String, dynamic>> result = await db.query(
      'pdu_schedules',
      limit: 1
    );
    
    // 기본 스케줄 생성 (데이터 없는 경우)
    if (result.isEmpty) {
      // UUID 생성
      final uuid = generateUUID();
      
      // 기본 스케줄 데이터
      final defaultSchedule = {
        'pdu_id': uuid, // UUID 사용
        'power_on_time': '09:00',
        'power_off_time': '18:00', 
        'days': '1,2,3,4,5',  // 월-금
        'is_active': 1
      };
      
      // 기본 스케줄 저장
      await db.insert('pdu_schedules', defaultSchedule);
      return defaultSchedule;
    }
    
    return result.first;
  }
} 