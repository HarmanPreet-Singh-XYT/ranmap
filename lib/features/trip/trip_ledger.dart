/// Pure ledger maths for a trip's shared expenses. Kept out of the widget so
/// the settlement can be unit-tested.
library;

/// A single "A pays B" settlement step.
typedef LedgerTransfer = ({String from, String to, double amount});

/// The currency symbol for [currency] (falls back to the code + space).
String ledgerSymbol(String currency) => switch (currency.toUpperCase()) {
  'USD' => r'$',
  'EUR' => '€',
  'GBP' => '£',
  'INR' => '₹',
  _ => '$currency ',
};

/// A human label for an expense category.
String ledgerCategoryLabel(String category) => switch (category) {
  'fuel' => 'Fuel',
  'food' => 'Food',
  'toll' => 'Tolls',
  'lodging' => 'Lodging',
  _ => 'Other',
};

/// Each member's net balance: what they paid minus their equal share.
///
/// Positive = they're owed money, negative = they owe.
Map<String, double> ledgersBalances({
  required Map<String, double> paidBy,
  required Iterable<String> memberIds,
  required double total,
}) {
  final ids = <String>{...memberIds, ...paidBy.keys};
  final share = total / (ids.isEmpty ? 1 : ids.length);
  return {for (final id in ids) id: (paidBy[id] ?? 0) - share};
}

/// Greedy equal-share settlement: pairs each net debtor with a net creditor.
/// Balances within [epsilon] are treated as zero, so nobody settles pennies.
List<LedgerTransfer> settleLedger(
  Map<String, double> balances, {
  double epsilon = 0.005,
}) {
  final debt = <String, double>{
    for (final e in balances.entries)
      if (e.value < -epsilon) e.key: -e.value,
  };
  final credit = <String, double>{
    for (final e in balances.entries)
      if (e.value > epsilon) e.key: e.value,
  };

  final out = <LedgerTransfer>[];
  for (final d in debt.keys.toList()) {
    for (final c in credit.keys.toList()) {
      if (debt[d]! < epsilon) break;
      if (credit[c]! < epsilon) continue;
      final amount = debt[d]! < credit[c]! ? debt[d]! : credit[c]!;
      out.add((from: d, to: c, amount: amount));
      debt[d] = debt[d]! - amount;
      credit[c] = credit[c]! - amount;
    }
  }
  return out;
}
