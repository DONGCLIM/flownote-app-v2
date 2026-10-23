import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../design/fn_scan_tokens.dart';
import '../../design/fn_shell.dart';

/// 갤러리 화면 — 사장님 시안 ① 1:1
///
/// OS 기본 피커는 우리가 화면을 못 그린다. 시안처럼 크림 배경·3열 그리드·
/// 코랄 강조로 보여주려면 앨범을 직접 읽어와야 해서 이 화면을 만들었다.
///
/// 흐름
///   권한 요청 → 최근 앨범 로드 → 3열 썸네일 → 탭으로 선택/해제
///   → '선택 완료 (N장)' → 고른 사진의 **원본 바이트**를 pop 으로 돌려준다
///
/// ⚠️ 웹에서는 `photo_manager` 가 동작하지 않는다. 웹은 이 화면에
///    들어오지 않고 기존 `GalleryIntake.pickAndPrepare` 를 그대로 쓴다.
///    (호출부 `ScanFlow.startFromGallery` 에서 분기한다)
class ScanGalleryDsScreen extends StatefulWidget {
  const ScanGalleryDsScreen({super.key, this.maxShots = 20});

  /// 한 번에 고를 수 있는 최대 장수. 시안 표기 `0/20장 선택`.
  final int maxShots;

  @override
  State<ScanGalleryDsScreen> createState() => _ScanGalleryDsScreenState();
}

/// 고른 사진 한 장. 화면 밖으로 나가는 결과물이다.
class PickedGalleryPhoto {
  const PickedGalleryPhoto({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class _ScanGalleryDsScreenState extends State<ScanGalleryDsScreen> {
  /// 한 번에 읽어올 사진 수. 스크롤 끝에 닿으면 더 읽는다.
  static const _pageSize = 60;

  /// 썸네일 해상도. 타일이 114dp 라 3배수로 충분하다.
  static const _thumb = ThumbnailSize(300, 375);

  List<AssetEntity> _assets = const [];
  final List<AssetEntity> _selected = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 0;
  AssetPathEntity? _album;

  /// 권한이 없거나 앨범을 못 읽었을 때 보여줄 안내.
  String? _blocked;

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _noMore) return;
    if (_scroll.position.pixels >
        _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    if (kIsWeb) {
      setState(() {
        _loading = false;
        _blocked = '웹에서는 갤러리 화면을 쓸 수 없어요.';
      });
      return;
    }
    final ps = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    if (!ps.hasAccess) {
      setState(() {
        _loading = false;
        _blocked = '사진 접근을 허용해주세요.';
      });
      return;
    }
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (!mounted) return;
    if (albums.isEmpty) {
      setState(() {
        _loading = false;
        _blocked = '사진이 없어요.';
      });
      return;
    }
    _album = albums.first;
    final list =
        await _album!.getAssetListPaged(page: 0, size: _pageSize);
    if (!mounted) return;
    setState(() {
      _assets = list;
      _loading = false;
      _noMore = list.length < _pageSize;
    });
  }

  Future<void> _loadMore() async {
    final a = _album;
    if (a == null) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    final list = await a.getAssetListPaged(page: next, size: _pageSize);
    if (!mounted) return;
    setState(() {
      _page = next;
      _assets = [..._assets, ...list];
      _loadingMore = false;
      _noMore = list.length < _pageSize;
    });
  }

  void _toggle(AssetEntity a) {
    setState(() {
      if (_selected.contains(a)) {
        _selected.remove(a);
      } else if (_selected.length < widget.maxShots) {
        _selected.add(a);
      }
    });
  }

  Future<void> _done() async {
    if (_selected.isEmpty) return;
    setState(() => _loading = true);
    final out = <PickedGalleryPhoto>[];
    for (final a in _selected) {
      final b = await a.originBytes;
      if (b == null) continue;
      out.add(PickedGalleryPhoto(name: await a.titleAsync, bytes: b));
    }
    if (!mounted) return;
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final n = _selected.length;
    return FnShell(
      navTitle: '갤러리',
      bg: FnScan.bg,
      onBack: () => Navigator.pop(context),
      child: Column(
        children: [
          _sectionRow(n),
          Expanded(child: _body()),
          _doneButton(n),
        ],
      ),
    );
  }

  /// 시안: `최근 항목` (왼쪽) / `0/20장 선택` (오른쪽)
  Widget _sectionRow(int n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          FnScan.galPad, 20, FnScan.galPad, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('최근 항목',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: FnScan.galSectionSize,
                fontWeight: FontWeight.w700,
                color: FnScan.ink,
              )),
          Text('$n/${widget.maxShots}장 선택',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: FnScan.ink,
              )),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: FnScan.coral));
    }
    final msg = _blocked;
    if (msg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                color: FnScan.sub,
              )),
        ),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: FnScan.galPad),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: FnScan.galCols,
        crossAxisSpacing: FnScan.galGapX,
        mainAxisSpacing: FnScan.galGapY,
        childAspectRatio: FnScan.galTileAspect,
      ),
      itemCount: _assets.length,
      itemBuilder: (_, i) => _tile(_assets[i]),
    );
  }

  Widget _tile(AssetEntity a) {
    final idx = _selected.indexOf(a);
    final on = idx >= 0;
    return GestureDetector(
      onTap: () => _toggle(a),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 썸네일. 시안은 모서리를 깎지 않은 네모다.
          FutureBuilder<Uint8List?>(
            future: a.thumbnailDataWithSize(_thumb),
            builder: (_, snap) {
              final b = snap.data;
              if (b == null) {
                return const ColoredBox(color: Color(0xFFEFEAE6));
              }
              return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true);
            },
          ),
          // 선택 동그라미 — 시안은 타일 우상단.
          Positioned(
            top: FnScan.galCheckInset,
            right: FnScan.galCheckInset,
            child: Container(
              width: FnScan.galCheck,
              height: FnScan.galCheck,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? FnScan.coral : Colors.white,
                border: Border.all(
                  color: on ? FnScan.coral : const Color(0xFFC8C8C8),
                ),
              ),
              child: on
                  ? Center(
                      child: Text('${idx + 1}',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          )),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  /// 시안: 흰 알약 버튼. 0장이면 회색 글자(비활성).
  Widget _doneButton(int n) {
    final on = n > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          FnScan.galPad, 14, FnScan.galPad, 20),
      child: GestureDetector(
        onTap: on ? _done : null,
        child: Container(
          height: FnScan.galBtnH,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? FnScan.coralBtn : FnScan.card,
            borderRadius: BorderRadius.circular(FnScan.galBtnRadius),
            boxShadow: FnScan.cardShadow,
          ),
          child: Text('선택 완료 ($n장)',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: on ? Colors.white : FnScan.muted,
              )),
        ),
      ),
    );
  }
}
