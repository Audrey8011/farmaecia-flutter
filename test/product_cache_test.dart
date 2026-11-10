import 'package:flutter_test/flutter_test.dart';
import 'package:farma_ecia_flutter/api_service.dart';

void main() {
  test('produto preserva seus dados ao preparar o registro offline', () {
    const product = Product(
      42,
      'Shampoo Nutritivo',
      'Cabelos',
      'Nutrição para os fios',
      25.90,
      '🧴',
    );

    final stored = product.toCacheMap();
    final restored = Product.fromJson(Map<String, dynamic>.from(stored));

    expect(restored.id, 42);
    expect(restored.name, 'Shampoo Nutritivo');
    expect(restored.category, 'Cabelos');
    expect(restored.price, 25.90);
    expect(restored.emoji, '🧴');
  });
}
