import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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
    // 데이터베이스 경로 설정
    String path = join(await getDatabasesPath(), 'remote_control.db');
    print('데이터베이스 경로: $path');
    
    // 데이터베이스 존재 여부 확인
    bool exists = await databaseExists(path);
    print('데이터베이스 존재 여부: $exists');
    
    print('데이터베이스 열기 시작');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        print('새 데이터베이스 생성: 테이블 생성 시작');
        await _onCreate(db, version);
        print('테이블 생성 완료');
      },
      onOpen: (db) {
        print('기존 데이터베이스 열기 성공');
      }
    );
    
    // 테이블 생성 확인
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    print('데이터베이스 테이블 목록: $tables');
    
    // 테이블 구조 확인
    final columns = await db.rawQuery("PRAGMA table_info(devices)");
    print('devices 테이블 구조: $columns');
    
    return db;
  }
  
  // 테이블이 존재하는지 확인하고 없으면 생성
  Future<void> _ensureTablesExist(Database db) async {
    // devices 테이블이 존재하는지 확인
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='devices'");
    
    if (tables.isEmpty) {
      print('devices 테이블이 존재하지 않아 새로 생성합니다.');
      await _onCreate(db, 1);
    } else {
      // 테이블 구조 확인
      final columns = await db.rawQuery("PRAGMA table_info(devices)");
      print('devices 테이블 구조: $columns');
      
      // ip 컬럼이 없으면 추가
      bool hasIpColumn = false;
      for (var column in columns) {
        if (column['name'] == 'ip') {
          hasIpColumn = true;
          break;
        }
      }
      
      if (!hasIpColumn) {
        print('ip 컬럼이 없어 추가합니다.');
        await db.execute('ALTER TABLE devices ADD COLUMN ip TEXT');
      }
      
      // 다른 필요한 컬럼도 확인 및 추가
      bool hasNetworkStatusColumn = false;
      bool hasExtraColumn = false;
      
      for (var column in columns) {
        if (column['name'] == 'network_status') {
          hasNetworkStatusColumn = true;
        }
        if (column['name'] == 'extra') {
          hasExtraColumn = true;
        }
      }
      
      if (!hasNetworkStatusColumn) {
        print('network_status 컬럼이 없어 추가합니다.');
        await db.execute("ALTER TABLE devices ADD COLUMN network_status TEXT DEFAULT 'unknown'");
      }
      
      if (!hasExtraColumn) {
        print('extra 컬럼이 없어 추가합니다.');
        await db.execute('ALTER TABLE devices ADD COLUMN extra TEXT');
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        ip TEXT NOT NULL,
        status TEXT DEFAULT 'offline',
        network_status TEXT DEFAULT 'unknown',
        extra TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_type TEXT NOT NULL,
        power_on_time TEXT NOT NULL,
        power_off_time TEXT NOT NULL,
        days TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE schedule_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        device_type TEXT NOT NULL,
        action TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');
  }

  // 장치 관련 메서드
  Future<List<Map<String, dynamic>>> getDevicesByType(String type) async {
    final db = await database;
    return await db.query('devices', where: 'type = ?', whereArgs: [type]);
  }

  Future<Map<String, dynamic>> getDeviceStatus(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'devices',
      where: 'id = ?',
      whereArgs: [id],
    );
    return result.first;
  }

  Future<void> updateDeviceIp(String id, String ip) async {
    final db = await database;
    await db.update(
      'devices',
      {'ip': ip},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateDeviceNetwork(String id, String ip, String mac) async {
    final db = await database;
    await db.update(
      'devices',
      {
        'ip': ip,
        'extra': '{"mac": "$mac"}',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updatePduConfig(String id, String ip, int ports) async {
    final db = await database;
    await db.update(
      'devices',
      {
        'ip': ip,
        'extra': '{"ports": $ports}',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> insertDevice(Map<String, dynamic> device) async {
    final db = await database;
    await db.insert(
      'devices',
      device,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 스케줄 관련 메서드
  Future<Map<String, dynamic>> getScheduleByType(String type) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'schedules',
      where: 'device_type = ?',
      whereArgs: [type],
    );
    return result.first;
  }

  Future<List<Map<String, dynamic>>> getAllSchedules() async {
    final db = await database;
    return await db.query('schedules');
  }

  Future<void> updateSchedule(String deviceType, String powerOnTime, String powerOffTime, String days) async {
    final db = await database;
    await db.insert(
      'schedules',
      {
        'device_type': deviceType,
        'power_on_time': powerOnTime,
        'power_off_time': powerOffTime,
        'days': days,
        'is_active': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getScheduleLogs() async {
    final db = await database;
    return await db.query(
      'schedule_logs',
      orderBy: 'timestamp DESC',
      limit: 100,
    );
  }

  Future<void> logScheduleExecution(String deviceType, String action, String status) async {
    final db = await database;
    await db.insert(
      'schedule_logs',
      {
        'timestamp': DateTime.now().toIso8601String(),
        'device_type': deviceType,
        'action': action,
        'status': status,
      },
    );
  }

  // 프로젝터 관련 메서드
  Future<List<Map<String, dynamic>>> getProjectors() async {
    final db = await database;
    return await db.query(
      'devices',
      where: 'type = ?',
      whereArgs: ['projector'],
    );
  }

  Future<int> addProjector(Map<String, dynamic> projector) async {
    final db = await database;
    
    print('프로젝터 추가 시작: ${projector.toString()}');
    
    // 테이블 확인
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='devices'");
    if (tables.isEmpty) {
      print('devices 테이블이 없어 새로 생성합니다.');
      await _onCreate(db, 1);
    }
    
    // 테이블 컬럼 확인
    final columns = await db.rawQuery("PRAGMA table_info(devices)");
    print('현재 테이블 구조: $columns');
    
    // 필요한 컬럼이 있는지 확인하고 없으면 추가
    bool hasIpColumn = false;
    bool hasNetworkStatusColumn = false;
    bool hasExtraColumn = false;
    
    for (var column in columns) {
      String colName = column['name'].toString();
      if (colName == 'ip') hasIpColumn = true;
      if (colName == 'network_status') hasNetworkStatusColumn = true;
      if (colName == 'extra') hasExtraColumn = true;
    }
    
    // 필요한 컬럼이 없으면 추가
    if (!hasIpColumn) {
      print('ip 컬럼 추가');
      await db.execute('ALTER TABLE devices ADD COLUMN ip TEXT');
    }
    
    if (!hasNetworkStatusColumn) {
      print('network_status 컬럼 추가');
      await db.execute("ALTER TABLE devices ADD COLUMN network_status TEXT DEFAULT 'unknown'");
    }
    
    if (!hasExtraColumn) {
      print('extra 컬럼 추가');
      await db.execute('ALTER TABLE devices ADD COLUMN extra TEXT');
    }
    
    // 데이터베이스에 삽입할 객체 생성
    final Map<String, dynamic> dbProjector = {
      'type': 'projector',
      'name': projector['name'],
      'ip': projector['ip'],
      'status': projector['status'] ?? 'offline',
      'network_status': projector['network_status'] ?? 'unknown',
      'extra': projector['extra'] ?? '{"model": "UNKNOWN", "username": "admin"}',
    };
    
    print('데이터베이스에 삽입할 데이터: $dbProjector');
    
    try {
      final id = await db.insert('devices', dbProjector);
      print('프로젝터 추가 성공, ID: $id');
      return id;
    } catch (e) {
      print('데이터베이스 삽입 오류: $e');
      
      // 오류 세부 정보 출력
      try {
        // 다시 시도: SQL 쿼리 직접 실행
        final List<Object?> values = [
          dbProjector['type'], 
          dbProjector['name'], 
          dbProjector['ip'], 
          dbProjector['status'], 
          dbProjector['network_status'], 
          dbProjector['extra']
        ];
        
        print('SQL 직접 실행: INSERT INTO devices (type, name, ip, status, network_status, extra) VALUES (?, ?, ?, ?, ?, ?)');
        print('SQL 파라미터: $values');
        
        final id = await db.rawInsert(
          'INSERT INTO devices (type, name, ip, status, network_status, extra) VALUES (?, ?, ?, ?, ?, ?)',
          values
        );
        
        print('직접 SQL 실행으로 프로젝터 추가 성공, ID: $id');
        return id;
      } catch (e2) {
        print('두 번째 시도 실패: $e2');
        rethrow;
      }
    }
  }

  Future<int> updateProjector(String id, Map<String, dynamic> projector) async {
    final db = await database;
    print('프로젝터 업데이트: ID=$id, 데이터=$projector');
    return await db.update(
      'devices',
      projector,
      where: 'id = ? AND type = ?',
      whereArgs: [id, 'projector'],
    );
  }

  Future<int> deleteProjector(String id) async {
    final db = await database;
    print('DB에서 프로젝터 삭제: ID = $id');
    return await db.delete(
      'devices',
      where: 'id = ? AND type = ?',
      whereArgs: [id, 'projector'],
    );
  }

  Future<Map<String, dynamic>?> getProjectorById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'devices',
      where: 'id = ? AND type = ?',
      whereArgs: [id, 'projector'],
    );
    
    if (result.isEmpty) {
      return null;
    }
    return result.first;
  }

  Future<Map<String, dynamic>?> getProjectorByIp(String ip) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'devices',
      where: 'ip = ? AND type = ?',
      whereArgs: [ip, 'projector'],
    );
    
    if (result.isEmpty) {
      return null;
    }
    return result.first;
  }

  // 프로젝터 네트워크 상태 업데이트
  Future<int> updateNetworkStatus(String ip, String networkStatus) async {
    final db = await database;
    
    try {
      return await db.update(
        'devices',
        {'network_status': networkStatus},
        where: 'ip = ?',
        whereArgs: [ip]
      );
    } catch (e) {
      print('네트워크 상태 업데이트 오류: $e');
      return 0;
    }
  }
  
  // 프로젝터 상태 업데이트
  Future<int> updateStatus(String ip, String status) async {
    final db = await database;
    
    try {
      return await db.update(
        'devices',
        {'status': status},
        where: 'ip = ?',
        whereArgs: [ip]
      );
    } catch (e) {
      print('장비 상태 업데이트 오류: $e');
      return 0;
    }
  }
} 