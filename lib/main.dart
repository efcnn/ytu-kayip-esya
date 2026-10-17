import 'dart:math' as math;

import 'package:flutter/material.dart';

// Firebase için
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

//ID leri kaydetmek için
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  // Flutter'ın çizim motorunun tamamen hazır olduğundan emin oluyoruz
  WidgetsFlutterBinding.ensureInitialized();
  
  // Uygulama başlamadan önce Firebase'i yapılandırma ayarlarıyla başlatıyoruz
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const KayipEsyaApp());
}

// ============================================================================
// SABİTLER
// ============================================================================

class Breakpoints {
  static const double tablet = 600; // form: dialog <-> tam ekran sınırı
  static const double desktop = 900; // AppBar butonları görünür, grid 3 sütun
  static const double wide = 1200; // grid 4 sütun
  static const double maxContent = 1280; // içerik maksimum genişliği
}

// ============================================================================
// MODELLER
// ============================================================================

enum ListingStatus {
  lost(
    label: 'Kayıp',
    color: Color(0xFFF2545B), 
    icon: Icons.search_off,
    formTitle: 'Eşyamı Kaybettim',
    formSubtitle:
        'Kaybettiğiniz eşyanın bilgilerini girin, ilanınız hemen yayınlansın.',
  ),
  found(
    label: 'Bulundu',
    color: Color(0xFF0056D2), 
    icon: Icons.inventory_2_outlined,
    formTitle: 'Kayıp Eşya Buldum',
    formSubtitle:
        'Bulduğunuz eşyayı paylaşın, sahibine ulaşmasına yardımcı olun.',
  );

  const ListingStatus({
    required this.label,
    required this.color,
    required this.icon,
    required this.formTitle,
    required this.formSubtitle,
  });

  final String label;
  final Color color;
  final IconData icon;
  final String formTitle;
  final String formSubtitle;
}

enum ListingFilter {
  all('Tümü'),
  lost('Kayıp'),
  found('Bulundu');

  const ListingFilter(this.label);
  final String label;
}

class Listing {
  const Listing({
    required this.id,
    required this.title,
    required this.location,
    required this.status,
    required this.contact,
    required this.createdAt,
    required this.expiresAt, // YENİ: Otomatik silinme tarihi
    this.imageUrl,
    this.personName, 
    this.droppedLocation,
  });

  final String id;
  final String title;
  final String location;
  final ListingStatus status;
  final String contact;
  final DateTime createdAt;
  final DateTime expiresAt; // YENİ
  final String? imageUrl;
  final String? personName;
  final String? droppedLocation;

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'location': location,
      'status': status.name,
      'contact': contact,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt), // YENİ: Firebase'e tarihi gönder
      'imageUrl': imageUrl,
      'personName': personName,
      'droppedLocation': droppedLocation,
    };
  }

  factory Listing.fromMap(Map<String, dynamic> map, String docId) {
    return Listing(
      id: docId,
      title: map['title'] ?? '',
      location: map['location'] ?? '',
      status: ListingStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => ListingStatus.lost,
      ),
      contact: map['contact'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (map['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now(), // YENİ
      imageUrl: map['imageUrl'],
      personName: map['personName'],
      droppedLocation: map['droppedLocation'],
    );
  }
}

String timeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'Az önce';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
  if (diff.inHours < 24) return '${diff.inHours} saat önce';
  return '${diff.inDays} gün önce';
}

// ============================================================================
// UYGULAMA
// ============================================================================

class KayipEsyaApp extends StatelessWidget {
  const KayipEsyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YTÜ Kayıp Eşya Platformu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF002D62), 
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white, 
      ),
      home: const HomePage(),
    );
  }
}

// ============================================================================
// ANA SAYFA
// ============================================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ListingFilter _filter = ListingFilter.all;
  String _query = '';

  Future<void> _openForm(ListingStatus kind) async {
    final Listing? result = await showListingForm(context, kind);
    if (result == null || !mounted) return;

    // Artık listeye manuel ekleme yapmıyoruz (setState sildik), 
    // çünkü Firebase Stream'i veriyi otomatik olarak ekranda güncelleyecek!

    final isWideScreen = MediaQuery.sizeOf(context).width >= Breakpoints.tablet;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: isWideScreen ? 420 : null,
          margin: isWideScreen ? null : const EdgeInsets.all(16),
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('İlanınız başarıyla eklendi')),
            ],
          ),
        ),
      );
  }

  

  List<String> _myListings = [];

  // initState içine hafızayı okuma kodunu ekle:
  @override
  void initState() {
    super.initState();
    _loadMyListings();
  }

  Future<void> _loadMyListings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myListings = prefs.getStringList('my_listings') ?? [];
    });
  }

  // İlanı silme fonksiyonu
  Future<void> _deleteListing(String id) async {
    await FirebaseFirestore.instance.collection('listings').doc(id).delete();
    // Hafızadan da temizle
    final prefs = await SharedPreferences.getInstance();
    _myListings.remove(id);
    await prefs.setStringList('my_listings', _myListings);
    setState(() {}); // Ekranı güncelle
    
    if (mounted) {
      Navigator.of(context).pop(); // Dialogu kapat
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İlan başarıyla silindi.')),
      );
    }
  }

  // Dialog penceresine çöp kutusunu ekle
  void _showDetails(Listing l) {
    final isMine = _myListings.contains(l.id);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(l.title)),
            if (isMine)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'İlanı Sil',
                onPressed: () {
                  _deleteListing(l.id);
                },
              ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusBadge(status: l.status),
              const SizedBox(height: 16),
              if (l.personName != null && l.personName!.isNotEmpty)
                _InfoRow(
                  icon: Icons.person_outline,
                  label: l.status == ListingStatus.lost ? 'Kaybeden Kişi' : 'Bulan Kişi',
                  value: l.personName!,
                ),
              _InfoRow(
                icon: Icons.place_outlined,
                label: l.status == ListingStatus.lost ? 'Kaybedilen Yer' : 'Bulunan Yer',
                value: l.location.isEmpty ? 'Belirtilmedi' : l.location,
              ),
              if (l.droppedLocation != null && l.droppedLocation!.isNotEmpty)
                _InfoRow(
                  icon: Icons.move_to_inbox_outlined,
                  label: 'Teslim Edilen / Bırakılan Yer',
                  value: l.droppedLocation!,
                ),
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'İletişim',
                value: l.contact,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final isWide = w >= Breakpoints.desktop;
        final columns = w >= Breakpoints.wide
            ? 4
            : w >= Breakpoints.desktop
                ? 3
                : w >= Breakpoints.tablet
                    ? 2
                    : 1;
        final basePad = w >= Breakpoints.desktop
            ? 32.0
            : w >= Breakpoints.tablet
                ? 24.0
                : 16.0;
        final side =
            math.max(basePad, (w - Breakpoints.maxContent) / 2 + basePad);
        final scheme = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            titleSpacing: isWide ? side : null,
            title: const BrandLogo(),
            actions: isWide
                ? [
                    KindButton(
                      kind: ListingStatus.lost,
                      onPressed: () => _openForm(ListingStatus.lost),
                    ),
                    const SizedBox(width: 12),
                    KindButton(
                      kind: ListingStatus.found,
                      onPressed: () => _openForm(ListingStatus.found),
                    ),
                    SizedBox(width: side),
                  ]
                : null,
          ),
          drawer: isWide
              ? null
              : AppDrawer(
                  onLost: () => _openForm(ListingStatus.lost),
                  onFound: () => _openForm(ListingStatus.found),
                ),
          // FIREBASE STREAM BAĞLANTISI BURADA BAŞLIYOR
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('listings')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Bir hata oluştu.'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // Firestore'dan gelen veriyi bizim Dart objelerine çeviriyoruz
              final allListings = snapshot.data!.docs
                  .map((doc) => Listing.fromMap(
                      doc.data() as Map<String, dynamic>, doc.id))
                  .toList();

              // Arama ve filtreleri uyguluyoruz
              final q = _query.trim().toLowerCase();
              final items = allListings.where((l) {
                final filterOk = _filter == ListingFilter.all ||
                    (_filter == ListingFilter.lost &&
                        l.status == ListingStatus.lost) ||
                    (_filter == ListingFilter.found &&
                        l.status == ListingStatus.found);
                final queryOk = q.isEmpty ||
                    l.title.toLowerCase().contains(q) ||
                    l.location.toLowerCase().contains(q);
                return filterOk && queryOk;
              }).toList();

              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, 24, side, 0),
                    sliver: SliverToBoxAdapter(
                      child: _Hero(
                        isWide: isWide,
                        onSearch: (v) => setState(() => _query = v),
                        onLost: () => _openForm(ListingStatus.lost),
                        onFound: () => _openForm(ListingStatus.found),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, 28, side, 16),
                    sliver: SliverToBoxAdapter(
                      child: _FilterBar(
                        selected: _filter,
                        count: items.length,
                        onChanged: (f) => setState(() => _filter = f),
                      ),
                    ),
                  ),
                  if (items.isEmpty)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: side),
                      sliver: const SliverToBoxAdapter(child: _EmptyState()),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: side),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          mainAxisExtent: 330,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => ListingCard(
                            listing: items[i],
                            onTap: () => _showDetails(items[i]),
                          ),
                          childCount: items.length,
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          'Kayıp Eşya • Firebase Entegreli Sürüm',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

// ============================================================================
// ÜST MENÜ / DRAWER / LOGO / BUTON
// ============================================================================

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8), 
          child: Image.asset(
            'assets/yildiz_logo.png',
            width: 36,         // Logonun genişliğini buradan ayarlayabilirsiniz
            height: 36,        // Logonun yüksekliğini buradan ayarlayabilirsiniz
            fit: BoxFit.cover, // Resmin kutuya nasıl sığacağı
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'YTÜ Kayıp Eşya Platformu',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF002D62),
              ),
        ),
      ],
    );
  }
}

class KindButton extends StatelessWidget {
  const KindButton({
    super.key,
    required this.kind,
    required this.onPressed,
    this.fullWidth = false,
  });

  final ListingStatus kind;
  final VoidCallback onPressed;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(kind.icon),
      label: Text(kind.formTitle),
      style: FilledButton.styleFrom(
        backgroundColor: kind.color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.onLost, required this.onFound});

  final VoidCallback onLost;
  final VoidCallback onFound;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: BrandLogo(),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Ana Sayfa'),
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: Icon(ListingStatus.lost.icon,
                  color: ListingStatus.lost.color),
              title: const Text('Eşyamı Kaybettim'),
              onTap: () {
                Navigator.of(context).pop();
                onLost();
              },
            ),
            ListTile(
              leading: Icon(ListingStatus.found.icon,
                  color: ListingStatus.found.color),
              title: const Text('Kayıp Eşya Buldum'),
              onTap: () {
                Navigator.of(context).pop();
                onFound();
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Text(
                'Kaybolan eşyaların sahiplerine kavuşması için bir araya geliyoruz.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// HERO, FİLTRE, BOŞ DURUM
// ============================================================================

class _Hero extends StatelessWidget {
  const _Hero({
    required this.isWide,
    required this.onSearch,
    required this.onLost,
    required this.onFound,
  });

  final bool isWide;
  final ValueChanged<String> onSearch;
  final VoidCallback onLost;
  final VoidCallback onFound;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: EdgeInsets.all(isWide ? 40 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        image: DecorationImage(
          image: const AssetImage('assets/ytu-davutpasa-kampusu.jpg'),
          fit: BoxFit.cover, // Görseli kapsayıcıya tam sığdırır
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.65), // Üzerindeki yazılar okunsun diye %65 oranında karartıyoruz
            BlendMode.darken,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kaybolan eşyalar sahiplerine kavuşsun',
            style: (isWide
                    ? theme.textTheme.displaySmall
                    : theme.textTheme.headlineSmall)
                ?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white, 
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              'Bir şey mi kaybettin ya da başkasına ait bir şey mi buldun? '
              'İlanları incele veya hemen yeni bir ilan oluştur.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white70,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: TextField(
              onChanged: onSearch,
              decoration: InputDecoration(
                hintText: 'Eşya adı veya konum ara…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: scheme.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (!isWide) ...[
            const SizedBox(height: 20),
            KindButton(
                kind: ListingStatus.lost, onPressed: onLost, fullWidth: true),
            const SizedBox(height: 10),
            KindButton(
                kind: ListingStatus.found, onPressed: onFound, fullWidth: true),
          ],
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.count,
    required this.onChanged,
  });

  final ListingFilter selected;
  final int count;
  final ValueChanged<ListingFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final f in ListingFilter.values)
                ChoiceChip(
                  label: Text(f.label),
                  selected: selected == f,
                  onSelected: (_) => onChanged(f),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$count ilan',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 56, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Aramanıza uygun ilan bulunamadı.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// İLAN KARTI
// ============================================================================

class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ListingImage(url: listing.imageUrl),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: StatusBadge(status: listing.status),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    listing.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.place_outlined,
                          size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          listing.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        timeAgo(listing.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingImage extends StatelessWidget {
  const _ListingImage({this.url});

  final String? url;

  Widget _placeholder(BuildContext context, {Widget? child}) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: child ??
            Icon(Icons.image_outlined,
                size: 48, color: scheme.onSurfaceVariant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null) return _placeholder(context);
    return Image.network(
      u,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        final total = progress.expectedTotalBytes;
        return _placeholder(
          context,
          child: CircularProgressIndicator(
            value: total != null ? progress.cumulativeBytesLoaded / total : null,
          ),
        );
      },
      errorBuilder: (context, error, stack) => _placeholder(context),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final ListingStatus status;

  @override
  Widget build(BuildContext context) {
    final isLost = status == ListingStatus.lost;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isLost ? Icons.search_off : Icons.check_circle,
              size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// FORM: EKRANA GÖRE DIALOG (PC) / TAM EKRAN SAYFA (MOBİL)
// ============================================================================

Future<Listing?> showListingForm(BuildContext context, ListingStatus kind) {
  final width = MediaQuery.sizeOf(context).width;

  if (width >= Breakpoints.tablet) {
    return showDialog<Listing>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
          child: ListingFormView(kind: kind, isDialog: true),
        ),
      ),
    );
  }

  return Navigator.of(context).push<Listing>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(kind.formTitle)),
        body: ListingFormView(kind: kind, isDialog: false),
      ),
    ),
  );
}

class ListingFormView extends StatefulWidget {
  const ListingFormView({
    super.key,
    required this.kind,
    required this.isDialog,
  });

  final ListingStatus kind;
  final bool isDialog;

  @override
  State<ListingFormView> createState() => _ListingFormViewState();
}

class _ListingFormViewState extends State<ListingFormView> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _itemCtrl = TextEditingController();
  final _placeCtrl = TextEditingController(); // Kayıp için "Nerede", Buluntu için "Nerede buldunuz"
  final _dropPlaceCtrl = TextEditingController(); // Buluntu için "Nereye teslim ettiniz"
  final _contactCtrl = TextEditingController();
  String? _photoName;

  bool get _isLost => widget.kind == ListingStatus.lost;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _itemCtrl.dispose();
    _placeCtrl.dispose();
    _dropPlaceCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Bu alan zorunludur' : null;

  String? _contactValidator(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Bu alan zorunludur';
    final isEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
    final digits = t.replaceAll(RegExp(r'\D'), '');
    if (!isEmail && digits.length < 10) {
      return 'Geçerli bir telefon numarası veya e-posta girin';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final docRef = FirebaseFirestore.instance.collection('listings').doc();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    
    // Şu anki tarihe 15 gün ekliyoruz
    final expireDate = DateTime.now().add(const Duration(days: 15));

    final listing = Listing(
      id: docRef.id,
      title: _itemCtrl.text.trim(),
      location: _placeCtrl.text.trim(),
      droppedLocation: _isLost ? null : _dropPlaceCtrl.text.trim(),
      status: widget.kind,
      contact: _contactCtrl.text.trim(),
      personName: _nameCtrl.text.trim(),
      createdAt: DateTime.now(),
      expiresAt: expireDate, // 15 gün sonrasını kaydet
      imageUrl: _photoName == null
          ? null
          : 'https://picsum.photos/seed/new$stamp/600/400',
    );

    await docRef.set(listing.toMap());

    // YENİ: Bu ilanın benim olduğunu cihaz hafızasına kaydet
    final prefs = await SharedPreferences.getInstance();
    final myListings = prefs.getStringList('my_listings') ?? [];
    myListings.add(docRef.id);
    await prefs.setStringList('my_listings', myListings);

    if (mounted) {
      Navigator.of(context).pop(listing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = widget.kind;
    const gap = SizedBox(height: 16);

    final photoField = PhotoPickerField(
      fileName: _photoName,
      onPick: () => setState(() => _photoName = 'esya_fotografi.jpg'),
      onClear: () => setState(() => _photoName = null),
    );

    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            kind.formSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // 1. İSİM ALANI (Artık her ikisi için de var ve zorunlu)
          _FormField(
            controller: _nameCtrl,
            label: _isLost ? 'Adınız / Soyadınız' : 'Bulan kişi / Adınız',
            icon: Icons.person_outline,
            validator: _required,
          ),
          gap,

          // 2. NE KAYBETTİNİZ / BULDUNUZ
          _FormField(
            controller: _itemCtrl,
            label: _isLost ? 'Ne kaybettiniz?' : 'Ne buldunuz?',
            hint: 'Örn: Siyah cüzdan, anahtar, çanta…',
            icon: Icons.label_outline,
            validator: _required,
          ),
          gap,

          // 3. KONUM ALANLARI
          if (_isLost) ...[
            // Kayıp için konum (Zorunlu Değil, validator: null yaptık)
            _FormField(
              controller: _placeCtrl,
              label: 'Hatırlıyorsanız, nerede kaybettiğinizi girin',
              icon: Icons.place_outlined,
              validator: null, 
            ),
            gap,
            photoField,
            gap,
          ] else ...[
            // Buluntu için Nerede Buldunuz (Zorunlu)
            _FormField(
              controller: _placeCtrl,
              label: 'Nerede buldunuz?',
              icon: Icons.place_outlined,
              validator: _required,
            ),
            gap,
            // Buluntu için Nereye Teslim Ettiniz (Zorunlu)
            _FormField(
              controller: _dropPlaceCtrl,
              label: 'Eşyayı nereye bıraktınız / teslim ettiniz?',
              icon: Icons.move_to_inbox_outlined,
              validator: _required,
            ),
            gap,
            photoField,
            gap,
          ],

          // 4. İLETİŞİM ALANI
          _FormField(
            controller: _contactCtrl,
            label: _isLost
                ? 'İletişim adresiniz / telefonunuz'
                : 'Size ulaşılabilecek iletişim adresi',
            hint: 'Telefon veya e-posta',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: _contactValidator,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.campaign_outlined),
            label: const Text('İlanı Yayınla'),
            style: FilledButton.styleFrom(
              backgroundColor: kind.color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isDialog)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: kind.color,
                  child: Icon(kind.icon, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    kind.formTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Kapat',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, widget.isDialog ? 8 : 20, 24, 24),
            child: form,
          ),
        ),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.validator,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// Dosya seçimini simüle eden alan (gerçek dosya seçici içermez).
class PhotoPickerField extends StatelessWidget {
  const PhotoPickerField({
    super.key,
    required this.fileName,
    required this.onPick,
    required this.onClear,
  });

  final String? fileName;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasFile = fileName != null;
    final radius = BorderRadius.circular(16);

    return Material(
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: hasFile ? scheme.primary : scheme.outlineVariant,
          width: hasFile ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: hasFile ? null : onPick,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: hasFile
              ? Row(
                  children: [
                    Icon(Icons.image, color: scheme.primary, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            'Fotoğraf eklendi',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kaldır',
                      icon: const Icon(Icons.close),
                      onPressed: onClear,
                    ),
                  ],
                )
              : Column(
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        size: 36, color: scheme.primary),
                    const SizedBox(height: 8),
                    Text('Fotoğraf yükle (isteğe bağlı)',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      'Dosya seçmek için tıklayın',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}