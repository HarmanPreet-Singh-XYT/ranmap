import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/core/widgets/brand/brand_card.dart';
import 'package:ranmap/core/widgets/brand/brand_data.dart';

void main() {
  // A vertical scrollable hands its children an *unbounded* height, and that is
  // what a two-per-row grid has to survive. `CrossAxisAlignment.stretch` on the
  // row was given that infinite height and threw "BoxConstraints forces an
  // infinite height" during layout — which blanked whole screens (Service &
  // maintenance, trip recap) while the header, laid out in an earlier frame,
  // stayed on screen.
  testWidgets('BrandStatGrid lays out inside an unbounded scrollable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              BrandStatGrid(
                tiles: [
                  BrandStatTile(label: 'Odometer', value: '1,200 km'),
                  BrandStatTile(label: 'Since service', value: '300 km'),
                  BrandStatTile(label: 'Interval', value: '10,000 km'),
                  BrandStatTile(label: 'Last service', value: '900 km'),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Odometer'), findsOneWidget);
    expect(find.text('Last service'), findsOneWidget);
  });

  testWidgets('a single trailing tile still lays out', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              BrandStatGrid(
                tiles: [
                  BrandStatTile(label: 'Only', value: '1'),
                  BrandStatTile(label: 'Second', value: '2'),
                  BrandStatTile(label: 'Third', value: '3'),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Third'), findsOneWidget);
  });
}
