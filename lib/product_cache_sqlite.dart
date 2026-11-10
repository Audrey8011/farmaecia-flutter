import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'api_service.dart';

class ProductCache {
  static Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;

    final databasePath = await getDatabasesPath();
    _database = await openDatabase(
      path.join(databasePath, 'farma_ecia_offline.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE produtos (
            id INTEGER PRIMARY KEY,
            nome TEXT NOT NULL,
            categoria TEXT NOT NULL,
            descricao TEXT NOT NULL,
            preco REAL NOT NULL,
            ilustracao TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE sincronizacao (
            chave TEXT PRIMARY KEY,
            valor TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<List<Product>> loadProducts() async {
    final rows = await (await _db).query('produtos', orderBy: 'nome COLLATE NOCASE');
    return rows.map(Product.fromJson).toList(growable: false);
  }

  Future<DateTime?> lastSyncAt() async {
    final rows = await (await _db).query(
      'sincronizacao',
      columns: ['valor'],
      where: 'chave = ?',
      whereArgs: ['catalogo'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['valor'] as String);
  }

  Future<void> saveProducts(List<Product> products, DateTime syncedAt) async {
    final database = await _db;
    await database.transaction((transaction) async {
      final batch = transaction.batch();
      batch.delete('produtos');
      for (final product in products) {
        batch.insert('produtos', product.toCacheMap());
      }
      batch.insert(
        'sincronizacao',
        {'chave': 'catalogo', 'valor': syncedAt.toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await batch.commit(noResult: true);
    });
  }
}
