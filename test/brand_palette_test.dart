import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/core/theme/brand_palette.dart';

void main() {
  tearDown(() => BrandColors.use(BrandPalette.light));

  test('ambient tokens follow the selected palette', () {
    BrandColors.use(BrandPalette.light);
    expect(BrandColors.surface, BrandPalette.light.surface);
    expect(BrandColors.primary, BrandPalette.light.primary);

    BrandColors.use(BrandPalette.dark);
    expect(BrandColors.surface, BrandPalette.dark.surface);
    expect(BrandColors.primary, BrandPalette.dark.primary);
    // The two palettes are genuinely different.
    expect(BrandPalette.light.surface, isNot(BrandPalette.dark.surface));
    expect(BrandPalette.light.primary, isNot(BrandPalette.dark.primary));
  });

  test('dark palette is dark and light palette is light', () {
    expect(BrandPalette.dark.canvas.computeLuminance(), lessThan(0.2));
    expect(BrandPalette.light.canvas.computeLuminance(), greaterThan(0.8));
  });
}
