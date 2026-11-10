import 'api_service.dart';

/// Fallback para plataformas sem armazenamento persistente configurado.
class ProductCache {
  static List<Product> _products = [];
  static DateTime? _syncedAt;

  Future<List<Product>> loadProducts() async => List.unmodifiable(_products);

  Future<DateTime?> lastSyncAt() async => _syncedAt;

  Future<void> saveProducts(List<Product> products, DateTime syncedAt) async {
    _products = List<Product>.of(products);
    _syncedAt = syncedAt;
  }
}
