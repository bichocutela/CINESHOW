import 'package:flutter/material.dart';

import 'core/models/media_item.dart';
import 'features/player/presentation/player_page.dart';

void main() {
  runApp(const CineShowApp());
}

class CineShowApp extends StatelessWidget {
  const CineShowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CINESHOW',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090A0F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE50914),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const ShellPage(),
    );
  }
}

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _selectedIndex = 0;

  static const _pages = <Widget>[
    HomePage(),
    SearchPage(),
    DownloadsPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        backgroundColor: const Color(0xFF0D0E14),
        indicatorColor: const Color(0x33E50914),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Buscar',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'Downloads',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const _titles = [
    ('O último horizonte', 'Drama  •  2026', Icons.landscape),
    ('Cidade em silêncio', 'Suspense  •  2025', Icons.location_city),
    ('Depois da meia-noite', 'Série  •  2024', Icons.nightlight_round),
  ];

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: const Color(0xFF090A0F),
          title: const Text(
            'CINESHOW',
            style: TextStyle(
              color: Color(0xFFE50914),
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          actions: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.cast_outlined),
              tooltip: 'Transmitir',
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none),
              tooltip: 'Notificações',
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: _HeroCard(
              item: _titles.first,
              onPlay: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PlayerPage(
                      media: MediaItem(
                        id: 'last-horizon',
                        title: 'O último horizonte',
                        description:
                            'Uma viagem para além do que parecia ser possível.',
                        genre: 'Drama',
                        year: 2026,
                        durationMinutes: 118,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: _SectionTitle(title: 'Continue assistindo'),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 172,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _titles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, index) => _PosterCard(item: _titles[index]),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: _SectionTitle(title: 'Escolhidos para você'),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (_, index) => _PosterCard(item: _titles[index % _titles.length]),
              childCount: 6,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.68,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.item, required this.onPlay});

  final (String, String, IconData) item;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF331018), Color(0xFF14151D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -36,
            top: 28,
            child: Icon(item.$3, size: 260, color: const Color(0x22FFFFFF)),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DESTAQUE DA SEMANA',
                  style: TextStyle(
                    color: Color(0xFFE50914),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.$1,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.$2,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Assistir agora'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.item});

  final (String, String, IconData) item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [Color(0xFF4A1823), Color(0xFF1D2738)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Icon(item.$3, size: 46, color: Colors.white38),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.$1,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            item.$2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderPage(
      icon: Icons.search,
      title: 'Buscar',
      message: 'Encontre filmes e séries quando o catálogo estiver conectado.',
    );
  }
}

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderPage(
      icon: Icons.download_outlined,
      title: 'Downloads',
      message: 'Seus conteúdos salvos para assistir offline aparecerão aqui.',
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderPage(
      icon: Icons.person_outline,
      title: 'Perfil',
      message: 'Preferências, conta e perfis serão adicionados nesta área.',
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56, color: const Color(0xFFE50914)),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
