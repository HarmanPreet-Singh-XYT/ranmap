import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/features/trip/trip_ledger.dart';

void main() {
  group('ledgersBalances', () {
    test('splits the total evenly against what each member paid', () {
      final balances = ledgersBalances(
        paidBy: {'a': 100, 'b': 0},
        memberIds: ['a', 'b'],
        total: 100,
      );
      expect(balances['a'], 50);
      expect(balances['b'], -50);
    });

    test('includes members who paid nothing', () {
      final balances = ledgersBalances(
        paidBy: {'a': 30},
        memberIds: ['a', 'b', 'c'],
        total: 30,
      );
      expect(balances['a'], 20);
      expect(balances['b'], -10);
      expect(balances['c'], -10);
    });

    test('is all-zero when everyone paid exactly their share', () {
      final balances = ledgersBalances(
        paidBy: {'a': 20, 'b': 20, 'c': 20},
        memberIds: ['a', 'b', 'c'],
        total: 60,
      );
      expect(balances.values.every((v) => v.abs() < 0.001), isTrue);
    });

    test('a member who underpaid shows as owing', () {
      final balances = ledgersBalances(
        paidBy: {'a': 10, 'b': 20, 'c': 30},
        memberIds: ['a', 'b', 'c'],
        total: 60,
      );
      expect(balances['a'], -10);
      expect(balances['b'], 0);
      expect(balances['c'], 10);
    });
  });

  group('settleLedger', () {
    test('pairs one debtor with one creditor', () {
      final transfers = settleLedger({'a': 50, 'b': -50});
      expect(transfers, hasLength(1));
      expect(transfers.single.from, 'b');
      expect(transfers.single.to, 'a');
      expect(transfers.single.amount, 50);
    });

    test('splits a creditor across multiple debtors', () {
      final transfers = settleLedger({'a': 30, 'b': -15, 'c': -15});
      expect(transfers, hasLength(2));
      expect(transfers.fold<double>(0, (s, t) => s + t.amount), 30);
      expect(transfers.every((t) => t.to == 'a'), isTrue);
      expect(transfers.map((t) => t.from).toSet(), {'b', 'c'});
    });

    test('leaves no transfers when everyone is square', () {
      expect(settleLedger({'a': 0, 'b': 0, 'c': 0.001}), isEmpty);
    });

    test('settles every balance to zero', () {
      final balances = {'a': 42.5, 'b': -10.25, 'c': -32.25};
      final transfers = settleLedger(balances);
      final net = <String, double>{for (final k in balances.keys) k: 0};
      for (final t in transfers) {
        net[t.from] = net[t.from]! + t.amount;
        net[t.to] = net[t.to]! - t.amount;
      }
      for (final id in balances.keys) {
        expect(net[id]! + balances[id]!, closeTo(0, 0.001));
      }
    });
  });

  test('ledgerSymbol and ledgerCategoryLabel', () {
    expect(ledgerSymbol('usd'), r'$');
    expect(ledgerSymbol('EUR'), '€');
    expect(ledgerSymbol('JPY'), 'JPY ');
    expect(ledgerCategoryLabel('fuel'), 'Fuel');
    expect(ledgerCategoryLabel('toll'), 'Tolls');
    expect(ledgerCategoryLabel('mystery'), 'Other');
  });
}
