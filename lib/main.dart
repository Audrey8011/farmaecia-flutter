import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'product_cache.dart';

void main() => runApp(const FarmaCiaApp());

const brand = Color(0xFFBD1E38);
const pale = Color(0xFFFFF0F2);
const canvas = Color(0xFFF4F5F9);
const ink = Color(0xFF20232B);

class FarmaCiaApp extends StatelessWidget {
  const FarmaCiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Farma&Cia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: canvas,
        colorScheme: ColorScheme.fromSeed(seedColor: brand, primary: brand),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: ink,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E4E9)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E4E9)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: brand, width: 1.5),
          ),
        ),
      ),
      home: const StoreShell(),
    );
  }
}

String brl(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

class StoreShell extends StatefulWidget {
  const StoreShell({super.key});
  @override
  State<StoreShell> createState() => _StoreShellState();
}

class _StoreShellState extends State<StoreShell> with WidgetsBindingObserver {
  int tab = 0;
  final Map<int, int> cart = {};
  final ProductCache _productCache = ProductCache();
  List<Product> products = [];
  String category = 'Todas';
  String query = '';
  bool loggedIn = false;
  bool loadingProducts = true;
  bool syncingProducts = false;
  bool isOnline = false;
  bool _networkAvailable = false;
  bool _cacheReady = false;
  bool submittingOrder = false;
  String? productsError;
  DateTime? lastProductsSync;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _syncRetryTimer;
  String? authToken;
  String customerName = 'Cliente';
  String? lastOrder;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);
    _checkConnectivity();
    _loadProducts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _syncRetryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _onConnectivityChanged(results);
    } catch (_) {
      if (_cacheReady) _syncProducts();
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    _networkAvailable = results.any((result) => result != ConnectivityResult.none);
    if (!_networkAvailable) {
      _syncRetryTimer?.cancel();
      if (mounted) setState(() => isOnline = false);
      return;
    }
    if (!_cacheReady) return;
    _syncProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final cachedProducts = await _productCache.loadProducts();
      final syncedAt = await _productCache.lastSyncAt();
      if (!mounted) return;
      setState(() {
        products = cachedProducts;
        lastProductsSync = syncedAt;
        loadingProducts = false;
        productsError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loadingProducts = false;
        productsError = 'Não foi possível ler o catálogo salvo neste aparelho.';
      });
    }
    _cacheReady = true;
    await _syncProducts();
  }

  Future<void> _syncProducts() async {
    if (syncingProducts) return;
    _syncRetryTimer?.cancel();
    if (mounted) setState(() => syncingProducts = true);

    try {
      final freshProducts = await ApiService.getProducts();
      final syncedAt = DateTime.now();
      Object? cacheError;
      try {
        await _productCache.saveProducts(freshProducts, syncedAt);
      } catch (error) {
        cacheError = error;
      }

      if (!mounted) return;
      setState(() {
        products = freshProducts;
        lastProductsSync = cacheError == null ? syncedAt : lastProductsSync;
        isOnline = true;
        productsError = cacheError == null
            ? null
            : 'Catálogo atualizado, mas não foi possível salvá-lo para uso offline.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isOnline = false;
        if (products.isEmpty) {
          productsError =
              'Sem conexão e sem catálogo salvo. Conecte-se à internet para carregar os produtos.';
        } else {
          productsError = null;
        }
      });
      if (_networkAvailable) {
        _syncRetryTimer = Timer(
          const Duration(seconds: 30),
          () => _syncProducts(),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          syncingProducts = false;
          loadingProducts = false;
        });
      }
    }
  }

  String get _catalogStatus {
    if (syncingProducts) return 'Sincronizando catálogo…';
    if (isOnline) return 'Online • catálogo atualizado';
    if (products.isEmpty) return 'Offline • nenhum catálogo salvo';
    final syncedAt = lastProductsSync;
    if (syncedAt == null) return 'Offline • usando catálogo salvo';
    final time =
        '${syncedAt.hour.toString().padLeft(2, '0')}:${syncedAt.minute.toString().padLeft(2, '0')}';
    return 'Offline • catálogo salvo (atualizado às $time)';
  }

  Product? _findProduct(int id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  int get itemCount => cart.values.fold(0, (a, b) => a + b);
  double get total => cart.entries.fold(
      0, (sum, entry) =>
          sum + (_findProduct(entry.key)?.price ?? 0) * entry.value);

  void add(Product product) {
    setState(() => cart[product.id] = (cart[product.id] ?? 0) + 1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} adicionado à cesta'),
        duration: const Duration(seconds: 1),
        backgroundColor: brand,
      ),
    );
  }

  void updateQuantity(int id, int change) {
    setState(() {
      final next = (cart[id] ?? 0) + change;
      if (next <= 0) {
        cart.remove(id);
      } else {
        cart[id] = next;
      }
    });
  }

  void openAuth({bool checkout = false}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AuthPage(
        onAuthenticated: (session) {
          setState(() {
            loggedIn = true;
            authToken = session.token;
            customerName = session.name.isEmpty ? 'Cliente' : session.name;
          });
          Navigator.pop(context);
          if (checkout) completeOrder();
        },
      ),
    ));
  }

  Future<void> completeOrder() async {
    if (cart.isEmpty || submittingOrder || authToken == null) return;
    setState(() => submittingOrder = true);
    try {
      final result = await ApiService.createOrder(
        token: authToken!,
        items: Map<int, int>.from(cart),
      );
      if (!mounted) return;
      lastOrder = 'FC-${result.id}';
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OrderSuccessPage(
          orderNumber: lastOrder!,
          total: result.total,
          items: Map<int, int>.from(cart),
          products: List<Product>.from(products),
          onBackHome: () {
            setState(() => cart.clear());
            Navigator.pop(context);
            setState(() => tab = 0);
          },
        ),
      ));
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível enviar o pedido à API.')));
      }
    } finally {
      if (mounted) setState(() => submittingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        products: products,
        loading: loadingProducts,
        error: productsError,
        onRetry: _loadProducts,
        category: category,
        query: query,
        onCategory: (value) => setState(() => category = value),
        onSearch: (value) => setState(() => query = value),
        onAdd: add,
      ),
      CartPage(
        cart: cart,
        products: products,
        onQuantity: updateQuantity,
        onShop: () => setState(() => tab = 0),
        onCheckout: () {
          if (submittingOrder) return;
          if (!loggedIn) {
            openAuth(checkout: true);
          } else {
            completeOrder();
          }
        },
      ),
      AccountPage(
        loggedIn: loggedIn,
        customerName: customerName,
        onLogin: () => openAuth(),
        onLogout: () => setState(() {
          loggedIn = false;
          authToken = null;
          customerName = 'Cliente';
        }),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: GestureDetector(
          onTap: () => setState(() => tab = 0),
          child: Row(
            children: [
              Image.asset(
                'assets/images/pharmacy_logo.png',
                width: 42,
                height: 42,
                fit: BoxFit.contain,
                semanticLabel: 'Logo da Farma&Cia',
              ),
              SizedBox(width: 7),
              Text('Farma&Cia',
                  style: TextStyle(
                      color: brand, fontWeight: FontWeight.w900, fontSize: 21)),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Minha cesta',
            onPressed: () => setState(() => tab = 1),
            icon: Badge(
              isLabelVisible: itemCount > 0,
              label: Text('$itemCount'),
              child: const Icon(Icons.shopping_bag_outlined),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: brand,
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: const Text(
              'Entrega rápida • Atendimento de confiança',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          Container(
            width: double.infinity,
            color: syncingProducts || isOnline
                ? const Color(0xFFEAF7EF)
                : const Color(0xFFFFF5E7),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(
                  syncingProducts
                      ? Icons.sync
                      : isOnline
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                  size: 16,
                  color: isOnline ? const Color(0xFF287A49) : brand,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _catalogStatus,
                    style: const TextStyle(fontSize: 11, color: ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: pages[tab]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Início'),
          NavigationDestination(
              icon: Badge(
                  isLabelVisible: itemCount > 0,
                  label: Text('$itemCount'),
                  child: const Icon(Icons.shopping_cart_outlined)),
              label: 'Cesta'),
          NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: loggedIn ? 'Conta' : 'Entrar'),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  final List<Product> products;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final String category, query;
  final ValueChanged<String> onCategory, onSearch;
  final ValueChanged<Product> onAdd;
  const HomePage({
    super.key,
    required this.products,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.category,
    required this.query,
    required this.onCategory,
    required this.onSearch,
    required this.onAdd,
  });

  Future<void> _showCategoryFilter(
      BuildContext context, List<String> categories) async {
    final selectedCategory = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Text('Filtrar por categoria',
                    style: TextStyle(
                        color: ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ),
              ...categories.map((option) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      category == option
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: category == option ? brand : Colors.grey,
                    ),
                    title: Text(option),
                    onTap: () => Navigator.pop(sheetContext, option),
                  )),
            ],
          ),
        ),
      ),
    );

    if (selectedCategory != null) onCategory(selectedCategory);
  }

  @override
  Widget build(BuildContext context) {
    const categories = [
      'Todas',
      'Bem-estar',
      'Cabelos',
      'Cuidados com a pele',
      'Higiene'
    ];
    final filtered = products.where((p) {
      final matchesCategory = category == 'Todas' || p.category == category;
      final matchesQuery = p.name.toLowerCase().contains(query.toLowerCase());
      return matchesCategory && matchesQuery;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverToBoxAdapter(
            child: TextField(
              onChanged: onSearch,
              decoration: InputDecoration(
                hintText: 'O que você procura?',
                prefixIcon: Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Filtrar por categoria',
                  onPressed: () => _showCategoryFilter(context, categories),
                  icon: Badge(
                    isLabelVisible: category != 'Todas',
                    child: const Icon(Icons.tune),
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: pale,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFF4D9DE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text('UM CARINHO A MAIS PARA VOCÊ',
                        style: TextStyle(
                            color: brand,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .5)),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: AspectRatio(
                        aspectRatio: 1.5,
                        child: Image.asset(
                          'assets/images/banner_farma_cia.jpeg',
                          fit: BoxFit.contain,
                          semanticLabel:
                              'Mulher apontando para a farmácia Farma e Cia',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Medicamentos, higiene, beleza e cuidados especiais para o seu dia a dia.',
                    style: TextStyle(color: Color(0xFF646B78), height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => onCategory('Todas'),
                    child: const Text('Ver produtos'),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.teal, size: 15),
                      SizedBox(width: 5),
                      Expanded(
                          child: Text('Compra simples e segura',
                              style: TextStyle(fontSize: 11))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Text('Nossos produtos',
                style: TextStyle(
                    color: ink, fontSize: 22, fontWeight: FontWeight.w900)),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final selected = category == categories[index];
                return ChoiceChip(
                  label: Text(categories[index]),
                  selected: selected,
                  onSelected: (_) => onCategory(categories[index]),
                  selectedColor: brand,
                  labelStyle: TextStyle(
                      color: selected ? Colors.white : ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                  side: BorderSide(
                      color: selected ? brand : const Color(0xFFE1E3E8)),
                );
              },
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: filtered.isEmpty
              ? loading
                  ? const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  : error != null
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Text(error!, textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: onRetry,
                                  child: const Text('Tentar novamente'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(child: Text('Nenhum produto encontrado.')),
                  ),
                )
              : SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => ProductCard(
                      product: filtered[index],
                      onAdd: () => onAdd(filtered[index]),
                    ),
                    childCount: filtered.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 258,
                  ),
                ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }
}

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onAdd;
  const ProductCard({super.key, required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFE7E8ED)),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: product.imageAsset == null
                    ? Container(
                        color: pale,
                        width: double.infinity,
                        child: Center(
                          child: Text(product.emoji,
                              style: const TextStyle(fontSize: 43)),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(6),
                        child: Image.asset(
                          product.imageAsset!,
                          width: double.infinity,
                          fit: BoxFit.contain,
                          semanticLabel: product.name,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(product.emoji,
                                style: const TextStyle(fontSize: 43)),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(product.category.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: brand,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .4)),
          const SizedBox(height: 4),
          Text(product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: ink, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 5),
          Text(brl(product.price),
              style: const TextStyle(
                  color: ink, fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: FilledButton(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800)),
              child: const Text('Adicionar à cesta'),
            ),
          ),
        ],
      ),
    );
  }
}

class CartPage extends StatelessWidget {
  final Map<int, int> cart;
  final List<Product> products;
  final void Function(int, int) onQuantity;
  final VoidCallback onShop, onCheckout;
  const CartPage({
    super.key,
    required this.cart,
    required this.products,
    required this.onQuantity,
    required this.onShop,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final entries = cart.entries.toList();
    final total = entries.fold<double>(0, (sum, entry) {
      final p = products.firstWhere((p) => p.id == entry.key);
      return sum + p.price * entry.value;
    });

    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE1E3E8))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shopping_cart_outlined,
                    size: 65, color: brand),
                const SizedBox(height: 16),
                const Text('Sua cesta está vazia',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: ink)),
                const SizedBox(height: 8),
                const Text(
                    'Explore nossos produtos e adicione seus favoritos à cesta.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF727987))),
                const SizedBox(height: 20),
                FilledButton(onPressed: onShop, child: const Text('Ver produtos')),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Minha cesta',
            style: TextStyle(
                fontSize: 27, color: ink, fontWeight: FontWeight.w900)),
        TextButton.icon(
          onPressed: onShop,
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Continuar comprando'),
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        ),
        const SizedBox(height: 8),
        ...entries.map((entry) {
          final p = products.firstWhere((p) => p.id == entry.key);
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE6E7EC))),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 55,
                      height: 55,
                      decoration: BoxDecoration(
                          color: pale,
                          borderRadius: BorderRadius.circular(13)),
                      child: Center(
                          child: Text(p.emoji,
                              style: const TextStyle(fontSize: 28))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, color: ink)),
                          Text(p.category,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                          Text(brl(p.price),
                              style: const TextStyle(
                                  color: brand, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22),
                Row(
                  children: [
                    const Text('Quantidade',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const Spacer(),
                    IconButton(
                        onPressed: () => onQuantity(p.id, -1),
                        icon: const Icon(Icons.remove_circle_outline)),
                    Text('${entry.value}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(
                        onPressed: () => onQuantity(p.id, 1),
                        icon: const Icon(Icons.add_circle_outline,
                            color: brand)),
                    const SizedBox(width: 8),
                    Text(brl(p.price * entry.value),
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          );
        }),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(19)),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Itens na cesta'),
                  Text('${cart.values.fold(0, (a, b) => a + b)}'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total dos produtos',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  Text(brl(total),
                      style: const TextStyle(
                          color: brand,
                          fontSize: 21,
                          fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: onCheckout,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Confirmar pedido'),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Você precisará entrar ou criar uma conta.',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

class AuthPage extends StatefulWidget {
  final ValueChanged<AuthSession> onAuthenticated;
  const AuthPage({super.key, required this.onAuthenticated});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool register = false;
  bool obscure = true;
  bool submitting = false;
  String? errorMessage;
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  final formKey = GlobalKey<FormState>();

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      submitting = true;
      errorMessage = null;
    });
    try {
      final session = register
          ? await ApiService.register(
              name: name.text.trim(),
              email: email.text.trim(),
              password: password.text,
            )
          : await ApiService.login(
              email: email.text.trim(),
              password: password.text,
            );
      if (mounted) widget.onAuthenticated(session);
    } on ApiException catch (error) {
      if (mounted) setState(() => errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => errorMessage =
            'Não foi possível acessar a API. Confira sua conexão e tente novamente.');
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sua conta')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(23),
                border: Border.all(color: const Color(0xFFE6E7EC))),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('SUA CONTA',
                      style: TextStyle(
                          color: brand,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Text(register ? 'Criar conta de cliente' : 'Entrar na Farma&Cia',
                      style: const TextStyle(
                          fontSize: 24,
                          color: ink,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(
                    register
                        ? 'Preencha seus dados para começar a comprar.'
                        : 'Informe seu e-mail e senha para continuar comprando.',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(errorMessage!,
                        style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 22),
                  if (register) ...[
                    const Text('Nome completo'),
                    const SizedBox(height: 7),
                    TextFormField(
                      controller: name,
                      validator: (v) =>
                          (v == null || v.trim().length < 2)
                              ? 'Informe seu nome'
                              : null,
                      decoration: const InputDecoration(hintText: 'Seu nome'),
                    ),
                    const SizedBox(height: 15),
                  ],
                  const Text('E-mail'),
                  const SizedBox(height: 7),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Informe um e-mail válido'
                        : null,
                    decoration:
                        const InputDecoration(hintText: 'seuemail@exemplo.com'),
                  ),
                  const SizedBox(height: 15),
                  const Text('Senha'),
                  const SizedBox(height: 7),
                  TextFormField(
                    controller: password,
                    obscureText: obscure,
                    validator: (v) => (v == null || v.length < 8)
                        ? 'A senha deve ter pelo menos 8 caracteres'
                        : null,
                    decoration: InputDecoration(
                      hintText: 'Mínimo de 8 caracteres',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                      ),
                    ),
                  ),
                  if (register) ...[
                    const SizedBox(height: 15),
                    const Text('Confirme sua senha'),
                    const SizedBox(height: 7),
                    TextFormField(
                      controller: confirm,
                      obscureText: true,
                      validator: (v) => v != password.text
                          ? 'As senhas não coincidem'
                          : null,
                      decoration:
                          const InputDecoration(hintText: 'Repita sua senha'),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: submitting ? null : _submit,
                      child: submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(register ? 'Criar conta' : 'Entrar'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () => setState(() {
                              register = !register;
                              errorMessage = null;
                            }),
                    child: Text(register
                        ? 'Já tem uma conta? Entrar'
                        : 'Não tem conta? Criar conta de cliente'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AccountPage extends StatelessWidget {
  final bool loggedIn;
  final String customerName;
  final VoidCallback onLogin, onLogout;
  const AccountPage({
    super.key,
    required this.loggedIn,
    required this.customerName,
    required this.onLogin,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(22)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
                radius: 34,
                backgroundColor: pale,
                child: Icon(Icons.person, color: brand, size: 36)),
            const SizedBox(height: 14),
            Text(loggedIn ? 'Olá, $customerName!' : 'Entre na sua conta',
                style: const TextStyle(
                    color: ink, fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
                loggedIn
                    ? 'Acesse sua conta e continue comprando na Farma&Cia.'
                    : 'Entre ou crie uma conta para finalizar seus pedidos.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 18),
            FilledButton(
                onPressed: loggedIn ? onLogout : onLogin,
                child: Text(loggedIn ? 'Sair da conta' : 'Entrar / Criar conta')),
          ],
        ),
      ),
    );
  }
}

class OrderSuccessPage extends StatelessWidget {
  final String orderNumber;
  final double total;
  final Map<int, int> items;
  final List<Product> products;
  final VoidCallback onBackHome;
  const OrderSuccessPage({
    super.key,
    required this.orderNumber,
    required this.total,
    required this.items,
    required this.products,
    required this.onBackHome,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmação do pedido')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(23),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 42,
                  backgroundColor: Color(0xFFE6F6EC),
                  child: Icon(Icons.check_circle,
                      color: Color(0xFF198754), size: 53),
                ),
                const SizedBox(height: 18),
                const Text('PEDIDO CONFIRMADO',
                    style: TextStyle(
                        color: Color(0xFF198754),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
                const SizedBox(height: 8),
                const Text('Compra realizada com sucesso!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: ink, fontSize: 23, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text(
                    'Obrigado por comprar na Farma&Cia. Seu pedido foi registrado.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: canvas, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      const Text('NÚMERO DO PEDIDO',
                          style: TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text(orderNumber,
                          style: const TextStyle(
                              color: brand,
                              fontSize: 22,
                              fontWeight: FontWeight.w900)),
                      const Divider(height: 24),
                      ...items.entries.map((entry) {
                        final p = products.firstWhere((p) => p.id == entry.key);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text('${p.name} x ${entry.value}',
                                      style: const TextStyle(fontSize: 12))),
                              Text(brl(p.price * entry.value),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        );
                      }),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total',
                              style: TextStyle(fontWeight: FontWeight.w900)),
                          Text(brl(total),
                              style: const TextStyle(
                                  color: brand,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        color: Color(0xFF198754)),
                    SizedBox(width: 8),
                    Flexible(
                        child: Text('Pedido recebido e aguardando processamento',
                            style: TextStyle(
                                color: Color(0xFF198754),
                                fontSize: 12,
                                fontWeight: FontWeight.w700))),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                      onPressed: onBackHome,
                      child: const Text('Voltar para o início')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
