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
    );
  }

  // ... rest of the existing code ... 
} 