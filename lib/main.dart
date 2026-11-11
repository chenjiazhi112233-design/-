import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain/packing.dart';

const navy = Color(0xFF102C3C);
const teal = Color(0xFF087F78);
const orange = Color(0xFFEF9D46);
const muted = Color(0xFF70818B);

void main() => runApp(const PalletApp());

class PalletApp extends StatelessWidget {
  const PalletApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '中亿联达智能打托',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansSC',
      colorScheme: ColorScheme.fromSeed(seedColor: teal, primary: teal),
      scaffoldBackgroundColor: const Color(0xFFF3F6F7),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: navy,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: navy,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: navy,
        ),
        bodyMedium: TextStyle(fontSize: 14, color: navy, height: 1.5),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF3F6F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
    home: const WorkspacePage(),
  );
}

class SavedPlan {
  final String id, name;
  final PackingInput input;
  final DateTime createdAt;
  SavedPlan(this.id, this.name, this.input, this.createdAt);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'input': input.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };
  factory SavedPlan.fromJson(Map<String, dynamic> json) => SavedPlan(
    json['id'] as String,
    json['name'] as String,
    PackingInput.fromJson(Map<String, dynamic>.from(json['input'] as Map)),
    DateTime.parse(json['createdAt'] as String),
  );
}

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key});
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  PackingInput input = PackingInput.defaults;
  late PackingResult result = calculatePacking(input);
  List<SavedPlan> plans = [];
  int tab = 0;
  bool loading = true;
  bool persisting = false;
  static const storageKey = 'zhongyi.plans.v1';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(storageKey) ?? [];
      final loaded = <SavedPlan>[];
      for (final value in raw) {
        try {
          final plan = SavedPlan.fromJson(
            jsonDecode(value) as Map<String, dynamic>,
          );
          calculatePacking(plan.input);
          loaded.add(plan);
        } catch (_) {
          /* Keep other plans readable if one record is damaged. */
        }
      }
      if (mounted) {
        setState(() {
          plans = loaded;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => loading = false);
        _message('无法读取本地方案，请稍后重试');
      }
    }
  }

  Future<bool> _persist(List<SavedPlan> next) async {
    if (persisting || loading) return false;
    setState(() => persisting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.setStringList(
        storageKey,
        next.map((p) => jsonEncode(p.toJson())).toList(),
      );
      if (!success) throw StateError('storage write failed');
      if (mounted) setState(() => plans = next);
      return true;
    } catch (_) {
      if (mounted) _message('保存失败，请检查设备存储空间');
      return false;
    } finally {
      if (mounted) setState(() => persisting = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    var draftName = '打托方案 ${plans.length + 1}';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存方案'),
        content: TextFormField(
          initialValue: draftName,
          onChanged: (value) => draftName = value,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '方案名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (draftName.trim().isNotEmpty) {
                Navigator.pop(context, draftName.trim());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    final now = DateTime.now();
    final ok = await _persist([
      SavedPlan(now.microsecondsSinceEpoch.toString(), name, input, now),
      ...plans,
    ]);
    if (ok && mounted) _message('已保存到本机方案库');
  }

  Future<void> _edit() async {
    final next = await showModalBottomSheet<PackingInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (context) => ParameterSheet(input: input),
    );
    if (next == null || !mounted) return;
    setState(() {
      input = next;
      result = calculatePacking(input);
    });
  }

  Future<void> _delete(SavedPlan plan) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除方案？'),
        content: Text('“${plan.name}”将从本机移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await _persist(plans.where((p) => p.id != plan.id).toList());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: IndexedStack(
            index: tab,
            children: [_calculator(), _library(), _about()],
          ),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (i) => setState(() => tab = i),
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFDCEFEA),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view_rounded),
          label: '智能打托',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_open_outlined),
          selectedIcon: Icon(Icons.folder_rounded),
          label: '方案库',
        ),
        NavigationDestination(
          icon: Icon(Icons.info_outline),
          selectedIcon: Icon(Icons.info),
          label: '使用说明',
        ),
      ],
    ),
  );

  Widget _header(String title, String subtitle) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: navy,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.view_in_ar_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: navy,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(color: teal, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        const Text('离线可用', style: TextStyle(fontSize: 11, color: teal)),
      ],
    ),
  );

  Widget _calculator() => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _header('中亿联达', 'INTELLIGENT PALLETIZING'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '每一寸空间，都有好方案。',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: navy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '输入箱规与托盘参数，快速生成码垛参考布局。',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 22),
            _summary(),
            const SizedBox(height: 18),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune_rounded, size: 19, color: teal),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '当前参数',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(onPressed: _edit, child: const Text('编辑参数')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _parameterRow(
                    '包装箱',
                    '${n(input.boxLength)} × ${n(input.boxWidth)} × ${n(input.boxHeight)} mm',
                    Icons.inventory_2_outlined,
                  ),
                  const Divider(height: 24, color: Color(0xFFEDF1F2)),
                  _parameterRow(
                    '托盘',
                    '${n(input.palletLength)} × ${n(input.palletWidth)} mm',
                    Icons.pallet,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _chip('限高 ${n(input.maxHeight)} mm'),
                      _chip('限载 ${n(input.maxLoad)} kg'),
                      _chip('箱重 ${n(input.boxWeight)} kg'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '单层布局预览',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _chip('俯视图', green: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${result.patternName} · 箱体仅水平旋转',
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 16),
                  AspectRatio(
                    aspectRatio: 1.25,
                    child: CustomPaint(painter: LayoutPainter(result)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: teal.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '包装箱',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          '间隙 ${n(input.gap)} mm · 留边 ${n(input.margin)} mm',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ),
                    ],
                  ),
                  if (result.layers > 1 &&
                      result.topLayerBoxes < result.boxesPerLayer)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '预览为首层；末层 ${result.topLayerBoxes} 箱，其余层每层 ${result.boxesPerLayer} 箱。',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _edit,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('调整参数'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: loading || persisting || !result.isFeasible
                        ? null
                        : _save,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('保存方案'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '计算采用规则排布启发式，不保证全局最优。实际作业前，请核验重心、承压、稳定性与设备限制。',
              style: TextStyle(fontSize: 11, height: 1.6, color: muted),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _summary() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: navy,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.auto_awesome_outlined,
              color: Color(0xFF89D9C8),
              size: 16,
            ),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                '推荐码垛方案',
                style: TextStyle(color: Color(0xFFB5D1D6), fontSize: 12),
              ),
            ),
            Text(
              result.isFeasible ? '已计算' : '无法码放',
              style: const TextStyle(color: Color(0xFF89D9C8), fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 5,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${result.totalBoxes}',
                      style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '箱 / 托',
                      style: TextStyle(fontSize: 14, color: Color(0xFFB5D1D6)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${(result.utilization * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF89D9C8),
                      ),
                    ),
                    const Text(
                      '首层面积利用率',
                      style: TextStyle(fontSize: 10, color: Color(0xFFB5D1D6)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 17),
          child: Divider(height: 1, color: Color(0xFF31505E)),
        ),
        Row(
          children: [
            _stat('每层箱位', '${result.boxesPerLayer} 箱'),
            _stat('码垛层数', '${result.layers} 层'),
            _stat('货物重量', '${n(result.totalWeight)} kg'),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '总高 ${n(result.packedHeight)} mm（含托盘） · ${result.limitingFactor}',
          style: const TextStyle(color: Color(0xFFB5D1D6), fontSize: 11),
        ),
      ],
    ),
  );

  Widget _stat(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFFB5D1D6)),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );

  Widget _parameterRow(String label, String value, IconData icon) => Row(
    children: [
      Icon(icon, size: 20, color: muted),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );

  Widget _library() => Column(
    children: [
      _header('方案库', 'YOUR PALLET PLANS'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '本机已保存 ${plans.length} 个方案',
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => tab = 0),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建方案'),
            ),
          ],
        ),
      ),
      Expanded(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : plans.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 60,
                        color: Color(0xFFB8C9CD),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '把好方案，留给下一次',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '在智能打托页面计算并保存，即可在这里查看。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
                itemCount: plans.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final plan = plans[index];
                  final r = calculatePacking(plan.input);
                  final d = plan.createdAt.toLocal();
                  return _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.layers_outlined, color: teal),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                plan.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '删除方案',
                              onPressed: persisting
                                  ? null
                                  : () => _delete(plan),
                              icon: const Icon(
                                Icons.delete_outline,
                                color: muted,
                                size: 21,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${n(plan.input.boxLength)} × ${n(plan.input.boxWidth)} × ${n(plan.input.boxHeight)} mm',
                          style: const TextStyle(fontSize: 13, color: muted),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${r.totalBoxes} 箱 / 托',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: teal,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => setState(() {
                              input = plan.input;
                              result = r;
                              tab = 0;
                            }),
                            child: const Text('载入方案'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    ],
  );

  Widget _about() => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _header('使用说明', 'BUILT FOR BETTER STACKING'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '让打托规划更清晰',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _card(
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '01  设置箱规与托盘',
                    style: TextStyle(fontWeight: FontWeight.w700, color: teal),
                  ),
                  SizedBox(height: 8),
                  Text('尺寸使用毫米，重量使用千克。总限高包含托盘自身高度；限载只计算货物重量。'),
                  SizedBox(height: 20),
                  Text(
                    '02  查看布局与约束',
                    style: TextStyle(fontWeight: FontWeight.w700, color: teal),
                  ),
                  SizedBox(height: 8),
                  Text('箱体保持直立，只允许在托盘平面旋转 90°。比较规则行列与混合朝向排布，选择每层箱位较多的候选方案。'),
                  SizedBox(height: 20),
                  Text(
                    '03  保存并复用',
                    style: TextStyle(fontWeight: FontWeight.w700, color: teal),
                  ),
                  SizedBox(height: 8),
                  Text('方案仅保存在本机，不上传到服务器。卸载应用会删除本地数据。'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _card(
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('计算边界', style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  Text(
                    '本工具提供几何布局和数量参考，不连接打托机或 PLC，不发送设备控制指令。计算不包含纸箱承压、重心、摩擦或运输稳定性分析，也不保证全局最优。请在实际作业前由现场人员确认方案。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Center(
              child: Text(
                '中亿联达 · 智能打托\nv1.0.0 / 离线规划工具',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.8, color: muted),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _card({required Widget child}) => Container(
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0xFFE7EDEF)),
  ),
  child: child,
);
Widget _chip(String text, {bool green = false}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
  decoration: BoxDecoration(
    color: green ? const Color(0xFFE5F3EE) : const Color(0xFFF1F5F6),
    borderRadius: BorderRadius.circular(7),
  ),
  child: Text(
    text,
    style: TextStyle(fontSize: 10, color: green ? teal : muted),
  ),
);
String n(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

class ParameterSheet extends StatefulWidget {
  final PackingInput input;
  const ParameterSheet({required this.input, super.key});
  @override
  State<ParameterSheet> createState() => _ParameterSheetState();
}

class _ParameterSheetState extends State<ParameterSheet> {
  late final Map<String, TextEditingController> fields;
  String? error;
  @override
  void initState() {
    super.initState();
    fields = {
      for (final entry in widget.input.toJson().entries)
        entry.key: TextEditingController(text: n(entry.value as num)),
    };
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply() {
    try {
      final values = <String, dynamic>{};
      for (final entry in fields.entries) {
        final value = double.tryParse(entry.value.text.trim());
        if (value == null || !value.isFinite) throw ArgumentError('请填写有效数字');
        values[entry.key] = value;
      }
      final next = PackingInput.fromJson(values);
      calculatePacking(next);
      Navigator.pop(context, next);
    } on ArgumentError catch (e) {
      setState(() => error = e.message.toString());
    }
  }

  Widget _field(String key, String label, String unit) => Expanded(
    child: TextField(
      controller: fields[key],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: unit),
    ),
  );
  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          children[i],
        ],
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 14, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '编辑打托参数',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
              children: [
                const Text(
                  '包装箱',
                  style: TextStyle(fontWeight: FontWeight.w700, color: teal),
                ),
                const SizedBox(height: 12),
                _row([
                  _field('boxLength', '箱长', 'mm'),
                  _field('boxWidth', '箱宽', 'mm'),
                ]),
                _row([
                  _field('boxHeight', '箱高', 'mm'),
                  _field('boxWeight', '单箱重量', 'kg'),
                ]),
                const SizedBox(height: 6),
                const Text(
                  '托盘与作业限制',
                  style: TextStyle(fontWeight: FontWeight.w700, color: teal),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final dims in [
                      [1200, 1000],
                      [1200, 800],
                      [1100, 1100],
                    ])
                      ActionChip(
                        label: Text('${dims[0]} × ${dims[1]}'),
                        onPressed: () {
                          fields['palletLength']!.text = '${dims[0]}';
                          fields['palletWidth']!.text = '${dims[1]}';
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _row([
                  _field('palletLength', '托盘长', 'mm'),
                  _field('palletWidth', '托盘宽', 'mm'),
                ]),
                _row([
                  _field('palletHeight', '托盘高度', 'mm'),
                  _field('maxHeight', '含托盘总限高', 'mm'),
                ]),
                _row([
                  _field('maxLoad', '货物限载', 'kg'),
                  _field('gap', '箱间间隙', 'mm'),
                ]),
                _row([_field('margin', '托盘留边', 'mm')]),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Color(0xFFB3261E)),
                    ),
                  ),
                const Text(
                  '箱体保持直立。间隙与留边会减少可用空间。',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('计算码垛方案'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class LayoutPainter extends CustomPainter {
  final PackingResult result;
  LayoutPainter(this.result);
  @override
  void paint(Canvas canvas, Size size) {
    final input = result.input;
    final scale = math.min(
      (size.width - 40) / input.palletLength,
      (size.height - 42) / input.palletWidth,
    );
    final width = input.palletLength * scale,
        height = input.palletWidth * scale;
    final origin = Offset((size.width - width) / 2, 13);
    final rect = origin & Size(width, height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(5)),
      Paint()..color = const Color(0xFFDFD2BC),
    );
    canvas.drawRect(rect, Paint()..color = const Color(0xFFF0E8DA));
    for (int i = 1; i < 7; i++) {
      canvas.drawLine(
        origin + Offset(width * i / 7, 0),
        origin + Offset(width * i / 7, height),
        Paint()
          ..color = const Color(0xFFE1D7C6)
          ..strokeWidth = 2,
      );
    }
    final placements = result.firstLayerPlacements;
    for (int i = 0; i < placements.length; i++) {
      final box = placements[i];
      final boxRect = Rect.fromLTWH(
        origin.dx + box.x * scale,
        origin.dy + box.y * scale,
        box.length * scale,
        box.width * scale,
      ).deflate(.8);
      if (boxRect.width <= 0 || boxRect.height <= 0) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(boxRect, const Radius.circular(3)),
        Paint()
          ..color = box.rotated
              ? const Color(0xFF6AB7A3)
              : const Color(0xFF39968D),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(boxRect, const Radius.circular(3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF24766F)
          ..strokeWidth = .6,
      );
      if (boxRect.shortestSide > 19 && placements.length <= 100) {
        final text = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(
          canvas,
          boxRect.center - Offset(text.width / 2, text.height / 2),
        );
      }
    }
    final text = TextPainter(
      text: TextSpan(
        text: '${n(input.palletLength)} × ${n(input.palletWidth)} mm',
        style: const TextStyle(fontSize: 11, color: muted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset((size.width - text.width) / 2, height + 23));
  }

  @override
  bool shouldRepaint(LayoutPainter oldDelegate) => oldDelegate.result != result;
}
