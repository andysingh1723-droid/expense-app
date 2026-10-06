import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

const rs = '\u20B9';
const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

void main() => runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
    home: const Home()));

class Tx {
  final String id, acc, bank, method, party, ref;
  final DateTime d;
  final double amt;
  final bool debit, manual;
  Tx(this.id, this.d, this.amt, this.debit, this.acc, this.bank, this.method, this.party, this.ref,
      {this.manual = false});
  Map<String, dynamic> toJson() => {
        'id': id, 'd': d.millisecondsSinceEpoch, 'a': amt, 'db': debit,
        'ac': acc, 'b': bank, 'm': method, 'p': party, 'r': ref
      };
  factory Tx.fromJson(Map<String, dynamic> j) => Tx(j['id'], DateTime.fromMillisecondsSinceEpoch(j['d']),
      (j['a'] as num).toDouble(), j['db'], j['ac'], j['b'], j['m'], j['p'], j['r'], manual: true);
}

final _skip = RegExp(
    r'otp|declined|failed|unsuccessful|insufficient|will be debited|scheduled|autopay|mandate|pre-?approved|loan offer|payment due|bill due|request',
    caseSensitive: false);
const _banks = {
  'kotak': 'Kotak Bank', 'hdfc': 'HDFC Bank', 'sbi': 'SBI', 'icici': 'ICICI Bank', 'axis': 'Axis Bank',
  'pnb': 'PNB', 'baroda': 'Bank of Baroda', 'canara': 'Canara Bank', 'yes bank': 'Yes Bank',
  'idfc': 'IDFC First', 'union bank': 'Union Bank', 'indusind': 'IndusInd', 'paytm': 'Paytm Bank',
  'federal': 'Federal Bank'
};

Tx? parse(String b, int ms, String sender) {
  if (b.isEmpty || _skip.hasMatch(b)) return null;
  final low = b.toLowerCase();
  final a = RegExp(r'(?:rs\.?|inr|\u20B9)\s*([\d,]+(?:\.\d+)?)', caseSensitive: false).firstMatch(b);
  if (a == null) return null;
  final amt = double.tryParse(a.group(1)!.replaceAll(',', ''));
  if (amt == null || amt <= 0) return null;
  final dm = RegExp(r'\b(?:debited|spent|paid|sent|withdrawn|purchase|transferred|debit)\b').firstMatch(low);
  final cm = RegExp(r'\b(?:credited|received|deposited|refund|salary)\b').firstMatch(low);
  if (dm == null && cm == null) return null;
  final debit = dm != null && (cm == null || dm.start < cm.start);
  final am = RegExp(r'(?:a/c|acct|account|card)\s*(?:no\.?|number|ending|ending with)?\s*[:\-]?\s*[xX*]*\s*(\d{4})\b',
              caseSensitive: false)
          .firstMatch(b) ??
      RegExp(r'[xX*]{2,}(\d{4})').firstMatch(b);
  final acc = am != null ? 'XX${am.group(1)}' : 'Unknown';
  var bank = 'Unknown';
  final hay = '$low ${sender.toLowerCase()}';
  for (final e in _banks.entries) {
    if (hay.contains(e.key)) {
      bank = e.value;
      break;
    }
  }
  final method = low.contains('upi')
      ? 'UPI'
      : low.contains('imps')
          ? 'IMPS'
          : low.contains('neft')
              ? 'NEFT'
              : low.contains('rtgs')
                  ? 'RTGS'
                  : low.contains('atm')
                      ? 'ATM'
                      : low.contains('card')
                          ? 'Card'
                          : 'Other';
  final rm = RegExp(r'(?:upi\s*ref(?:erence)?|ref(?:erence)?\s*(?:no|number)?|utr|rrn)\s*[:.\-]?\s*(\d{6,})',
          caseSensitive: false)
      .firstMatch(b);
  final ref = rm?.group(1) ?? '';
  final pm = RegExp(
          debit
              ? r'(?:\bto\b|\bat\b|vpa)\s+([A-Za-z0-9@._\- ]{3,35}?)(?=\s+(?:on|ref|upi|via|dated|avl|bal|utr|if)\b|[.,;(]|$)'
              : r'(?:\bfrom\b|\bby\b|vpa)\s+([A-Za-z0-9@._\- ]{3,35}?)(?=\s+(?:on|ref|upi|via|dated|avl|bal|utr|if)\b|[.,;(]|$)',
          caseSensitive: false)
      .firstMatch(b);
  final party = (pm?.group(1) ?? '-').trim();
  final id = ref.isNotEmpty ? 'r${ref}_${debit ? 'd' : 'c'}' : '${ms}_${amt}_${debit}_$acc';
  return Tx(id, DateTime.fromMillisecondsSinceEpoch(ms), amt, debit, acc, bank, method,
      party.isEmpty ? '-' : party, ref);
}

String two(int n) => n.toString().padLeft(2, '0');
String tm(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String dt(DateTime d) => '${d.day} ${mon[d.month - 1]} ${d.year}';
String money(double v) {
  final s = v.floor().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  final frac = v - v.floor();
  if (frac > 0.004) b.write('.${(frac * 100).round().toString().padLeft(2, '0')}');
  return '$rs$b';
}

double spent(List<Tx> l) => l.where((t) => t.debit).fold<double>(0, (s, t) => s + t.amt);
double got(List<Tx> l) => l.where((t) => !t.debit).fold<double>(0, (s, t) => s + t.amt);

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<Tx> sms = [], manual = [];
  final seen = <String>{};
  Map<String, String> names = {}, alias = {};
  double budget = 10000;
  String status = 'Loading...', q = '', type = 'all', src = 'all', range = 'all', mode = 'tx';
  int rd = 30;
  int? pieSel;
  bool listening = false;
  SharedPreferences? sp;
  final qc = TextEditingController();

  @override
  void initState() {
    super.initState();
    boot();
  }

  Future<void> boot() async {
    sp = await SharedPreferences.getInstance();
    budget = sp!.getDouble('budget') ?? 10000;
    names = Map<String, String>.from(jsonDecode(sp!.getString('names') ?? '{}'));
    alias = Map<String, String>.from(jsonDecode(sp!.getString('alias') ?? '{}'));
    manual = (jsonDecode(sp!.getString('manual') ?? '[]') as List)
        .map((e) => Tx.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    await load();
  }

  Future<void> load() async {
    final t = Telephony.instance;
    if (await t.requestSmsPermissions != true) {
      setState(() => status = 'SMS permission nahi mili. Allow karke refresh dabao.');
      return;
    }
    final inbox = await t.getInboxSms(
        columns: [SmsColumn.BODY, SmsColumn.DATE, SmsColumn.ADDRESS],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)]);
    final list = <Tx>[];
    final ids = <String>{};
    for (final m in inbox) {
      final x = parse(m.body ?? '', m.date ?? 0, m.address ?? '');
      if (x != null && ids.add(x.id)) list.add(x);
    }
    seen
      ..clear()
      ..addAll(ids);
    if (!mounted) return;
    setState(() {
      sms = list;
      status = '';
    });
    if (!listening) {
      listening = true;
      t.listenIncomingSms(onNewMessage: onSms, listenInBackground: false);
    }
  }

  void onSms(SmsMessage m) {
    final x = parse(m.body ?? '', m.date ?? DateTime.now().millisecondsSinceEpoch, m.address ?? '');
    if (x != null && seen.add(x.id) && mounted) setState(() => sms.insert(0, x));
  }

  void saveManual() => sp?.setString('manual', jsonEncode(manual.map((e) => e.toJson()).toList()));
  void saveNames() {
    sp?.setString('names', jsonEncode(names));
    sp?.setString('alias', jsonEncode(alias));
  }

  List<Tx> get all => [...sms, ...manual];
  String nm(Tx t) => names[t.id] ?? alias[t.party.toLowerCase()] ?? (t.party == '-' ? 'Unknown' : t.party);

  String dayLabel(DateTime d) {
    final n = DateTime.now();
    final a = DateTime(d.year, d.month, d.day), b = DateTime(n.year, n.month, n.day);
    final diff = b.difference(a).inDays;
    return diff == 0 ? 'Today' : diff == 1 ? 'Yesterday' : dt(d);
  }

  List<Tx> filtered() {
    final now = DateTime.now();
    final from = range == '7'
        ? now.subtract(const Duration(days: 7))
        : range == '30'
            ? now.subtract(const Duration(days: 30))
            : range == 'm'
                ? DateTime(now.year, now.month)
                : null;
    final s = q.trim().toLowerCase();
    final out = all.where((t) {
      if (type == 'exp' && !t.debit) return false;
      if (type == 'inc' && t.debit) return false;
      if (src != 'all' && t.bank != src && t.acc != src) return false;
      if (from != null && t.d.isBefore(from)) return false;
      if (s.isEmpty) return true;
      final hay =
          '${nm(t)} ${t.party} ${t.bank} ${t.acc} ${t.method} ${t.ref} ${t.amt} ${t.amt.round()} ${t.debit ? 'debit expense sent' : 'credit income received'}'
              .toLowerCase();
      return hay.contains(s);
    }).toList();
    out.sort((a, b) => b.d.compareTo(a.d));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mera Kharcha'),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: load)],
          bottom: const TabBar(tabs: [Tab(text: 'Transactions'), Tab(text: 'Reports')]),
        ),
        floatingActionButton: FloatingActionButton(onPressed: addManual, child: const Icon(Icons.add)),
        body: status.isNotEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(status)))
            : TabBarView(children: [txTab(), reportTab()]),
      ),
    );
  }

  Widget txTab() {
    final f = filtered();
    final srcs = <String>{
      for (final t in all) ...[if (t.bank != 'Unknown') t.bank, if (t.acc != 'Unknown') t.acc]
    };
    final sv = srcs.contains(src) ? src : 'all';
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: TextField(
          controller: qc,
          onChanged: (v) => setState(() => q = v),
          decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Naam, bank, 8916, amount, UPI...',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        qc.clear();
                        setState(() => q = '');
                      })),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          for (final e in const {'all': 'All', 'exp': 'Expense', 'inc': 'Income'}.entries)
            Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                    label: Text(e.value), selected: type == e.key, onSelected: (_) => setState(() => type = e.key))),
          const SizedBox(width: 6),
          DropdownButton<String>(
              value: sv,
              items: [
                const DropdownMenuItem(value: 'all', child: Text('Sab bank/account')),
                for (final s in srcs) DropdownMenuItem(value: s, child: Text(s))
              ],
              onChanged: (v) => setState(() => src = v ?? 'all')),
          const SizedBox(width: 12),
          DropdownButton<String>(
              value: range,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Sab dates')),
                DropdownMenuItem(value: '7', child: Text('7 din')),
                DropdownMenuItem(value: '30', child: Text('30 din')),
                DropdownMenuItem(value: 'm', child: Text('Is mahine')),
              ],
              onChanged: (v) => setState(() => range = v ?? 'all')),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${f.length} txns'),
          Text('In ${money(got(f))}', style: const TextStyle(color: Colors.green)),
          Text('Out ${money(spent(f))}', style: const TextStyle(color: Colors.red)),
          Text('Net ${got(f) - spent(f) < 0 ? '-' : ''}${money((got(f) - spent(f)).abs())}'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'tx', label: Text('Transactions')),
            ButtonSegment(value: 'ppl', label: Text('People'))
          ],
          selected: {mode},
          onSelectionChanged: (s) => setState(() => mode = s.first),
        ),
      ),
      Expanded(child: mode == 'tx' ? txList(f) : peopleList(f)),
    ]);
  }

  Widget txList(List<Tx> f) {
    if (f.isEmpty) return const Center(child: Text('Koi transaction nahi mila'));
    final items = <Object>[];
    String? last;
    for (final t in f) {
      final k = dayLabel(t.d);
      if (k != last) {
        items.add(k);
        last = k;
      }
      items.add(t);
    }
    return ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) {
          final it = items[i];
          if (it is String) {
            return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(it, style: const TextStyle(fontWeight: FontWeight.bold)));
          }
          return tile(it as Tx);
        });
  }

  Widget tile(Tx t) => ListTile(
        onTap: () => detail(t),
        isThreeLine: true,
        leading: Icon(t.debit ? Icons.arrow_upward : Icons.arrow_downward,
            color: t.debit ? Colors.red : Colors.green),
        title: Text(nm(t), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${dt(t.d)} \u2022 ${tm(t.d)}\n${t.bank} \u2022 ${t.acc} \u2022 ${t.method}'),
        trailing: Text('${t.debit ? '-' : '+'}${money(t.amt)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: t.debit ? Colors.red : Colors.green)),
      );

  Widget peopleList(List<Tx> f) {
    if (f.isEmpty) return const Center(child: Text('Koi transaction nahi mila'));
    final g = <String, List<Tx>>{};
    for (final t in f) {
      (g[nm(t).toLowerCase()] ??= []).add(t);
    }
    final keys = g.keys.toList()
      ..sort((a, b) => (spent(g[b]!) + got(g[b]!)).compareTo(spent(g[a]!) + got(g[a]!)));
    return ListView.builder(
        itemCount: keys.length,
        itemBuilder: (_, i) {
          final l = g[keys[i]]!;
          return ListTile(
            onTap: () => personSheet(nm(l.first), l),
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(nm(l.first), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${l.length} transactions\nLast: ${dt(l.first.d)}'),
            isThreeLine: true,
            trailing: Text('Sent ${money(spent(l))}'),
          );
        });
  }

  void personSheet(String title, List<Tx> l) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            builder: (_, sc) => ListView(controller: sc, children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text('Total sent: ${money(spent(l))}'),
                        Text('Total received: ${money(got(l))}'),
                        Text('Net: ${got(l) - spent(l) < 0 ? '-' : ''}${money((got(l) - spent(l)).abs())}'),
                        Text('Transactions: ${l.length}'),
                      ])),
                  const Divider(height: 1),
                  for (final t in l) tile(t),
                ])));
  }

  void detail(Tx t) {
    showModalBottomSheet(
        context: context,
        builder: (_) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.debit ? 'Expense' : 'Income', style: TextStyle(color: t.debit ? Colors.red : Colors.green)),
              Text(money(t.amt), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(nm(t), style: const TextStyle(fontSize: 18)),
              if (nm(t) != t.party && t.party != '-') Text('Original: ${t.party}'),
              const SizedBox(height: 8),
              Text('${dt(t.d)}  ${tm(t.d)}'),
              Text('Bank: ${t.bank}'),
              Text('Account: ${t.acc}'),
              Text('Method: ${t.method}'),
              if (t.ref.isNotEmpty) Text('Reference: ${t.ref}'),
              const SizedBox(height: 12),
              Row(children: [
                OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      rename(t);
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Naam badlo')),
                if (t.manual) ...[
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => manual.removeWhere((x) => x.id == t.id));
                        saveManual();
                      },
                      child: const Text('Delete'))
                ]
              ]),
            ])));
  }

  void rename(Tx t) {
    final c = TextEditingController(text: nm(t));
    var grp = false;
    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, ss) => AlertDialog(
                  title: const Text('Naam badlo'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(controller: c, autofocus: true),
                    if (t.party != '-')
                      CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: grp,
                          onChanged: (v) => ss(() => grp = v ?? false),
                          title: const Text('Is party ke sabhi transactions ka')),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () {
                          final n = c.text.trim();
                          setState(() {
                            if (n.isEmpty) {
                              names.remove(t.id);
                              if (grp) alias.remove(t.party.toLowerCase());
                            } else if (grp) {
                              alias[t.party.toLowerCase()] = n;
                              names.remove(t.id);
                            } else {
                              names[t.id] = n;
                            }
                          });
                          saveNames();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Save'))
                  ],
                )));
  }

  void addManual() {
    final a = TextEditingController(), n = TextEditingController();
    var deb = true;
    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, ss) => AlertDialog(
                  title: const Text('Manual transaction'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: a,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Amount')),
                    TextField(controller: n, decoration: const InputDecoration(labelText: 'Naam / description')),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('Expense')),
                          ButtonSegment(value: false, label: Text('Income'))
                        ],
                        selected: {deb},
                        onSelectionChanged: (s) => ss(() => deb = s.first)),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () {
                          final v = double.tryParse(a.text);
                          if (v == null || v <= 0) return;
                          final now = DateTime.now();
                          setState(() => manual.add(Tx('m${now.microsecondsSinceEpoch}', now, v, deb, 'Manual',
                              'Manual', 'Cash', n.text.trim().isEmpty ? '-' : n.text.trim(), '',
                              manual: true)));
                          saveManual();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Add'))
                  ],
                )));
  }

  Widget reportTab() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: rd - 1));
    final l = all.where((t) => !t.d.isBefore(start)).toList();
    final days = List.generate(rd, (i) => start.add(Duration(days: i)));
    final ex = List<double>.filled(rd, 0), inc = List<double>.filled(rd, 0), cnt = List<int>.filled(rd, 0);
    for (final t in l) {
      final i = t.d.difference(start).inDays;
      if (i < 0 || i >= rd) continue;
      (t.debit ? ex : inc)[i] += t.amt;
      cnt[i]++;
    }
    final byAcc = <String, double>{}, accCnt = <String, int>{};
    for (final t in l.where((t) => t.debit)) {
      final k = t.bank == 'Unknown' || t.bank == t.acc ? t.acc : '${t.bank} ${t.acc}';
      byAcc[k] = (byAcc[k] ?? 0) + t.amt;
      accCnt[k] = (accCnt[k] ?? 0) + 1;
    }
    final keys = byAcc.keys.toList();
    final monthSpent = spent(all.where((t) => t.d.year == now.year && t.d.month == now.month).toList());
    final over = monthSpent > budget;
    final step = rd <= 7 ? 1 : rd <= 15 ? 2 : 5;
    final colors = [Colors.blue, Colors.orange, Colors.green, Colors.purple, Colors.red, Colors.teal];
    final net = got(l) - spent(l);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, children: [
        for (final e in const {7: '7 Days', 15: '15 Days', 30: '1 Month'}.entries)
          ChoiceChip(
              label: Text(e.value),
              selected: rd == e.key,
              onSelected: (_) => setState(() {
                    rd = e.key;
                    pieSel = null;
                  }))
      ]),
      const SizedBox(height: 8),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Expense: ${money(spent(l))}', style: const TextStyle(color: Colors.red)),
                Text('Income: ${money(got(l))}', style: const TextStyle(color: Colors.green)),
                Text('Net: ${net < 0 ? '-' : ''}${money(net.abs())}'),
                Text('Transactions: ${l.length}'),
              ]))),
      Card(
        child: ListTile(
          title: Text('Is mahine: ${money(monthSpent)} / ${money(budget)}'),
          subtitle: Text(over ? 'Budget cross ho gaya!' : 'Budget ke andar',
              style: TextStyle(color: over ? Colors.red : Colors.green)),
          trailing: IconButton(icon: const Icon(Icons.edit), onPressed: editBudget),
        ),
      ),
      const SizedBox(height: 12),
      const Text('Daily kharcha (bar dabao)', style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(
        height: 220,
        child: BarChart(BarChartData(
          barGroups: [
            for (var i = 0; i < rd; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(toY: ex[i], color: Colors.blue, width: rd <= 7 ? 18 : rd <= 15 ? 12 : 6)
              ])
          ],
          barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, gi, r, ri) => BarTooltipItem(
                      '${dt(days[gi])}\nExpense ${money(ex[gi])}\nIncome ${money(inc[gi])}\n${cnt[gi]} txns',
                      const TextStyle(color: Colors.white, fontSize: 12)))),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) => v.toInt() % step == 0 && v.toInt() < rd
                        ? Text('${days[v.toInt()].day}', style: const TextStyle(fontSize: 11))
                        : const SizedBox())),
          ),
        )),
      ),
      const SizedBox(height: 20),
      const Text('Account-wise kharcha (hissa dabao)', style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(
        height: 220,
        child: PieChart(PieChartData(
          pieTouchData: PieTouchData(touchCallback: (e, r) {
            if (e is FlTapUpEvent) {
              final i = r?.touchedSection?.touchedSectionIndex;
              setState(() => pieSel = (i == null || i < 0) ? null : i);
            }
          }),
          sections: [
            for (var i = 0; i < keys.length; i++)
              PieChartSectionData(
                  value: byAcc[keys[i]],
                  title: keys[i],
                  radius: pieSel == i ? 80 : 70,
                  titleStyle: const TextStyle(fontSize: 9, color: Colors.white),
                  color: colors[i % colors.length])
          ],
        )),
      ),
      if (pieSel != null && pieSel! < keys.length)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${keys[pieSel!]}: ${money(byAcc[keys[pieSel!]]!)} \u2022 ${accCnt[keys[pieSel!]]} transactions',
                style: const TextStyle(fontWeight: FontWeight.bold))),
    ]);
  }

  void editBudget() {
    final c = TextEditingController(text: budget.toStringAsFixed(0));
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Monthly budget'),
              content: TextField(controller: c, keyboardType: TextInputType.number),
              actions: [
                TextButton(
                    onPressed: () {
                      setState(() => budget = double.tryParse(c.text) ?? budget);
                      sp?.setDouble('budget', budget);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save'))
              ],
            ));
  }
}
