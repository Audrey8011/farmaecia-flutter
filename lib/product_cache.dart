import 'api_service.dart';
import 'product_cache_stub.dart'
    if (dart.library.io) 'product_cache_sqlite.dart'
    if (dart.library.html) 'product_cache_web.dart' as platform;

/// Cache multiplataforma: SQLite no mobile e armazenamento local no navegador.
class ProductCache {
  final platform.ProductCache _storage = platform.ProductCache();

  Future<List<Product>> loadProducts() => _storage.loadProducts();

  Future<DateTime?> lastSyncAt() => _storage.lastSyncAt();

  Future<void> saveProducts(List<Product> products, DateTime syncedAt) =>
      _storage.saveProducts(products, syncedAt);
}
