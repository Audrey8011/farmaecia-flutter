import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');

String get _apiBaseUrl {
  if (_configuredApiBaseUrl.isNotEmpty) return _configuredApiBaseUrl;
  if (kIsWeb) return 'http://localhost:5178/api';
  if (defaultTargetPlatform == TargetPlatform.android) {
    // O emulador Android acessa a máquina host por este endereço reservado.
    return 'http://10.0.2.2:5178/api';
  }
  return 'http://localhost:5178/api';
}

class Product {
  final int id;
  final String name, category, description, emoji;
  final double price;

  const Product(this.id, this.name, this.category, this.description,
      this.price, this.emoji);

  Map<String, Object?> toCacheMap() => {
        'id': id,
        'nome': name,
        'categoria': category,
        'descricao': description,
        'preco': price,
        'ilustracao': emoji,
      };

  String? get imageAsset {
    final normalizedName = name.toLowerCase();
    if (normalizedName.contains('álcool') ||
        normalizedName.contains('alcool')) {
      return 'assets/images/produtos/alcool-em-gel-70.jpeg';
    }
    if (normalizedName.contains('condicionador')) {
      return 'assets/images/produtos/condicionador-suave.jpeg';
    }
    if (normalizedName.contains('creme para as mãos') ||
        normalizedName.contains('creme para as maos')) {
      return 'assets/images/produtos/creme-para-maos.jpeg';
    }
    if (normalizedName.contains('gelatina')) {
      return 'assets/images/produtos/gelatina-salon-line.jpeg';
    }
    if (normalizedName.contains('kit de higiene bucal')) {
      return 'assets/images/produtos/kit-higiene-bucal.jpeg';
    }
    if (normalizedName.contains('protetor solar')) {
      return 'assets/images/produtos/protetor-solar-fps50.jpeg';
    }
    if (normalizedName.contains('sabonete')) {
      return 'assets/images/produtos/sabonete-liquido.jpeg';
    }
    if (normalizedName.contains('shampoo')) {
      return 'assets/images/produtos/shampoo-nutritivo.jpeg';
    }
    if (normalizedName.contains('hidratante')) {
      return 'assets/images/produtos/locao-deo-hidratante.jpeg';
    }
    return null;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final category = json['categoria'] as String? ?? '';
    final name = json['nome'] as String? ?? '';
    final illustration = json['ilustracao'] as String? ?? '';
    final emoji = illustration.trim().isEmpty || illustration == '?'
        ? _emojiFor(category, name)
        : illustration;
    return Product(
      json['id'] as int,
      name,
      category,
      json['descricao'] as String? ?? '',
      (json['preco'] as num).toDouble(),
      emoji,
    );
  }

  static String _emojiFor(String category, String name) {
    if (name.toLowerCase().contains('solar')) return '☀️';
    if (name.toLowerCase().contains('álcool')) return '🧴';
    if (category == 'Cabelos') return '🧴';
    if (category == 'Higiene') return '🪥';
    if (category == 'Bem-estar') return '🍊';
    return '🧴';
  }
}

class AuthSession {
  final String token;
  final int userId;
  final String name;

  const AuthSession(this.token, this.userId, this.name);

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        json['token'] as String,
        json['usuarioId'] as int,
        json['nome'] as String,
      );
}

class OrderResult {
  final int id;
  final double total;

  const OrderResult(this.id, this.total);

  factory OrderResult.fromJson(Map<String, dynamic> json) =>
      OrderResult(json['id'] as int, (json['total'] as num).toDouble());
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

class ApiService {
  static final _client = http.Client();
  static Uri _uri(String path) => Uri.parse('$_apiBaseUrl$path');

  static Future<List<Product>> getProducts() async {
    final response = await _client
        .get(_uri('/produtos'))
        .timeout(const Duration(seconds: 20));
    _ensureSuccess(response);
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((item) => Product.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _client
        .post(
          _uri('/auth/registrar'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'nome': name, 'email': email, 'senha': password}),
        )
        .timeout(const Duration(seconds: 20));
    _ensureSuccess(response);
    return AuthSession.fromJson(jsonDecode(response.body));
  }

  static Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final response = await _client
        .post(
          _uri('/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'senha': password}),
        )
        .timeout(const Duration(seconds: 20));
    _ensureSuccess(response);
    return AuthSession.fromJson(jsonDecode(response.body));
  }

  static Future<OrderResult> createOrder({
    required String token,
    required Map<int, int> items,
  }) async {
    final response = await _client
        .post(
          _uri('/pedidos'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'itens': items.entries
                .map((entry) => {
                      'produtoId': entry.key,
                      'quantidade': entry.value,
                    })
                .toList(),
          }),
        )
        .timeout(const Duration(seconds: 20));
    _ensureSuccess(response);
    return OrderResult.fromJson(jsonDecode(response.body));
  }

  static void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    var message = 'Não foi possível concluir a solicitação.';
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        message = body['message'] as String? ??
            body['title'] as String? ??
            message;
      }
    } on FormatException {
      // Mantém a mensagem amigável quando a API não retorna JSON.
    }
    throw ApiException(message);
  }
}
