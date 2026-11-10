// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import 'api_service.dart';

class ProductCache {
  static const _productsKey = 'farma_ecia_offline_products_v1';
  static const _syncedAtKey = 'farma_ecia_offline_products_synced_at_v1';

  Future<List<Product>> loadProducts() async {
    final cached = html.window.localStorage[_productsKey];
    if (cached == null || cached.isEmpty) return const [];

    try {
      final decoded = jsonDecode(cached) as List<dynamic>;
      return decoded
          .map((item) => Product.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList(growable: false);
    } on FormatException {
      html.window.localStorage.remove(_productsKey);
      return const [];
    } on TypeError {
      html.window.localStorage.remove(_productsKey);
      return const [];
    }
  }

  Future<DateTime?> lastSyncAt() async {
    final value = html.window.localStorage[_syncedAtKey];
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> saveProducts(List<Product> products, DateTime syncedAt) async {
    html.window.localStorage[_productsKey] = jsonEncode(
      products.map((product) => product.toCacheMap()).toList(growable: false),
    );
    html.window.localStorage[_syncedAtKey] = syncedAt.toIso8601String();
  }
}
