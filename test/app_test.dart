import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhongyi_pallet/domain/packing.dart';
import 'package:zhongyi_pallet/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets(
      'edit, validate, save, reload and delete at ${size.width.toInt()} px',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const PalletApp());
        await tester.pumpAndSettle();
        expect(find.text('50'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _tapVisible(tester, find.text('编辑参数'));
        expect(find.byType(ParameterSheet), findsOneWidget);
        final length = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == '箱长',
        );
        await tester.enterText(length, 'abc');
        await _sheetScrollTo(tester, find.text('计算码垛方案'));
        await tester.tap(find.text('计算码垛方案'));
        await tester.pumpAndSettle();
        expect(find.text('请填写有效数字'), findsOneWidget);
        expect(find.byType(ParameterSheet), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _sheetScrollTo(tester, length, delta: -300);
        await tester.enterText(length, '600');
        await _sheetScrollTo(tester, find.text('计算码垛方案'));
        await tester.tap(find.text('计算码垛方案'));
        await tester.pumpAndSettle();
        expect(find.byType(ParameterSheet), findsNothing);
        expect(find.text('30'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _tapVisible(tester, find.text('保存方案'));
        final dialogField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        final name = '${size.width.toInt()} 回归方案';
        await tester.enterText(dialogField, name);
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('zhongyi.plans.v1'), hasLength(1));
        expect(tester.takeException(), isNull);

        // Recreate the whole app to prove the library is loaded from persistence.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(const PalletApp());
        await tester.pumpAndSettle();
        expect(find.text('50'), findsOneWidget);
        await tester.tap(find.text('方案库'));
        await tester.pumpAndSettle();
        expect(find.text(name), findsOneWidget);
        expect(find.text('30 箱 / 托'), findsOneWidget);
        await _tapVisible(tester, find.text('载入方案'));
        expect(find.text('30'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('方案库'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('删除方案'));
        await tester.pumpAndSettle();
        expect(find.text('删除方案？'), findsOneWidget);
        await tester.tap(find.text('删除'));
        await tester.pumpAndSettle();
        expect(find.text(name), findsNothing);
        expect(find.text('本机已保存 0 个方案'), findsOneWidget);
        expect(prefs.getStringList('zhongyi.plans.v1'), isEmpty);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('使用说明'));
        await tester.pumpAndSettle();
        expect(find.text('让打托规划更清晰'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('one corrupted saved record does not hide other plans', (
    tester,
  ) async {
    final record = SavedPlan(
      'valid-id',
      '有效方案',
      PackingInput.defaults,
      DateTime(2026, 11, 12),
    );
    SharedPreferences.setMockInitialValues({
      'zhongyi.plans.v1': ['{broken json', jsonEncode(record.toJson())],
    });
    await tester.pumpWidget(const PalletApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('方案库'));
    await tester.pumpAndSettle();
    expect(find.text('本机已保存 1 个方案'), findsOneWidget);
    expect(find.text('有效方案'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing preserves sub-gram weight and fractional dimensions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ParameterSheet(
            input: PackingInput.defaults.copyWith(
              boxWeight: 0.001,
              boxLength: 400.123,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final weight = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '单箱重量',
      ),
    );
    final length = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == '箱长',
      ),
    );
    expect(weight.controller!.text, '0.001');
    expect(length.controller!.text, '400.123');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _sheetScrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 300,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final scrollable = find.descendant(
    of: find.byType(ParameterSheet),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );
  await tester.scrollUntilVisible(finder, delta, scrollable: scrollable);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
