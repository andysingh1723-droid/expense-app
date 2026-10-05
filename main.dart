import 'package:flutter/material.dart';  
import 'package:another_telephony/telephony.dart';  
import 'package:fl_chart/fl_chart.dart';  
  
const String rs = '\u20B9'; // Rupee symbol (encoding-safe)  
const Color incomeColor = Color(0xFF2E9E6B);  
const Color expenseColor = Color(0xFFE5534B);  
  
void main() => runApp(const MyApp());  
  
class MyApp extends StatelessWidget {  
  const MyApp({super.key});  
  
  ThemeData _theme(Brightness b) => ThemeData(  
        useMaterial3: true,  
        colorScheme: ColorScheme.fromSeed(  
            seedColor: const Color(0xFF3F51B5), brightness: b),  
      );  
  
  @override  
  Widget build(BuildContext context) => MaterialApp(  
        debugShowCheckedModeBanner: false,  
        title: 'Mera Kharcha',  
        theme: _theme(Brightness.light),  
        darkTheme: _theme(Brightness.dark),  
        themeMode: ThemeMode.system,  
        home: const Home(),  
      );  
}  
  
// ---------------- DATA + PARSING (unchanged logic) ----------------  
  
class Tx {  
  final DateTime d;  
  final double amt;  
  final String acc, to;  
  final bool debit;  
  Tx(this.d, this.amt, this.acc, this.to, this.debit);  
}  
  
Tx? parse(String b, int ms) {  
  final low = b.toLowerCase();  
  if (low.contains('otp')) return null;  
  final a = RegExp('(?:rs\\.?|inr|\u20B9)\\s*([\\d,]+(?:\\.\\d+)?)',  
          caseSensitive: false)  
      .firstMatch(b);  
  if (a == null) return null;  
  final debit = RegExp(r'debited|spent|paid|sent|withdrawn').hasMatch(low);  
  final credit = RegExp(r'credited|received|deposited').hasMatch(low);  
  if (!debit && !credit) return null;  
  final amt = double.tryParse(a.group(1)!.replaceAll(',', ''));  
  if (amt == null) return null;  
  final ac = RegExp(r'(?:a/c|acct|account|card)[^\d]{0,12}(\d{3,4})',  
          caseSensitive: false)  
      .firstMatch(b);  
  final to = RegExp(  
          r'(?:to|at|from|vpa)\s+([A-Za-z0-9@._ ]{3,30}?)(?:\s+on|\s+ref|\.|,|$)',  
          caseSensitive: false)  
      .firstMatch(b);  
  return Tx(DateTime.fromMillisecondsSinceEpoch(ms), amt,  
      ac != null ? 'XX${ac.group(1)}' : 'Unknown',  
      to?.group(1)?.trim() ?? '-', debit);  
}  
  
// ---------------- HOME ----------------  
  
class Home extends StatefulWidget {  
  const Home({super.key});  
  @override  
  State<Home> createState() => _HomeState();  
}  
  
class _HomeState extends State<Home> {  
  List<Tx> txs = []; // SMS se  
  final List<Tx> manual = []; // FAB se add kiye hue  
  String status = 'Loading...';  
  double budget = 10000;  
  int tab = 0;  
  int filter = 0; // 0 all, 1 income, 2 expense  
  
  static const months = [  
    'January', 'February', 'March', 'April', 'May', 'June',  
    'July', 'August', 'September', 'October', 'November', 'December'  
  ];  
  static const days = [  
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'  
  ];  
  
  @override  
  void initState() {  
    super.initState();  
    load();  
  }  
  
  Future<void> load() async {  
    final t = Telephony.instance;  
    final ok = await t.requestSmsPermissions;  
    if (ok != true) {  
      setState(() => status = 'SMS permission nahi mili');  
      return;  
    }  
    final sms = await t.getInboxSms(  
        columns: [SmsColumn.BODY, SmsColumn.DATE],  
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)]);  
    final list = <Tx>[];  
    for (final m in sms) {  
      final x = parse(m.body ?? '', m.date ?? 0);  
      if (x != null) list.add(x);  
    }  
    setState(() {  
      txs = list;  
      status = list.isEmpty ? 'Koi transaction SMS nahi mila' : '';  
    });  
  }  
  
  String two(int n) => n.toString().padLeft(2, '0');  
  
  String money(double v, [int dec = 0]) {  
    final s = v.abs().toStringAsFixed(dec);  
    final parts = s.split('.');  
    var i = parts[0];  
    if (i.length > 3) {  
      final last3 = i.substring(i.length - 3);  
      var rest = i.substring(0, i.length - 3);  
      rest = rest.replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+$)'), (m) => '${m[1]},');  
      i = '$rest,$last3';  
    }  
    return '${v < 0 ? "-" : ""}$rs$i${dec > 0 ? ".${parts[1]}" : ""}';  
  }  
  
  List<Tx> get all {  
    final l = [...manual, ...txs];  
    l.sort((a, b) => b.d.compareTo(a.d));  
    return l;  
  }  
  
  double sumFor(DateTime m, bool debit) => all  
      .where((t) => t.debit == debit && t.d.year == m.year && t.d.month == m.month)  
      .fold<double>(0, (s, t) => s + t.amt);  
  
  String dayLabel(DateTime d) {  
    final n = DateTime.now();  
    final today = DateTime(n.year, n.month, n.day);  
    final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;  
    if (diff == 0) return 'Today';  
    if (diff == 1) return 'Yesterday';  
    return '${d.day} ${months[d.month - 1].substring(0, 3)} ${d.year}';  
  }  
  
  // ---------- shared widgets ----------  
  
  Widget card(Widget child, {EdgeInsets? pad, VoidCallback? onTap}) {  
    final cs = Theme.of(context).colorScheme;  
    return Card(  
      elevation: 0,  
      margin: EdgeInsets.zero,  
      clipBehavior: Clip.antiAlias,  
      color: cs.surfaceContainerLow,  
      shape: RoundedRectangleBorder(  
          borderRadius: BorderRadius.circular(20),  
          side: BorderSide(color: cs.outlineVariant.withOpacity(0.5))),  
      child: InkWell(  
        onTap: onTap,  
        child: Padding(padding: pad ?? const EdgeInsets.all(16), child: child),  
      ),  
    );  
  }  
  
  Widget page(List<Widget> children) => SafeArea(  
        child: Center(  
          child: ConstrainedBox(  
            constraints: const BoxConstraints(maxWidth: 640),  
            child: ListView(  
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),  
                children: children),  
          ),  
        ),  
      );  
  
  Widget title(String t, {Widget? trailing}) => Padding(  
        padding: const EdgeInsets.only(top: 24, bottom: 8),  
        child: Row(children: [  
          Expanded(  
              child: Text(t,  
                  style: Theme.of(context)  
                      .textTheme  
                      .titleMedium  
                      ?.copyWith(fontWeight: FontWeight.w700))),  
          if (trailing != null) trailing,  
        ]),  
      );  
  
  Widget empty(IconData ic, String t, String sub) {  
    final cs = Theme.of(context).colorScheme;  
    return Padding(  
      padding: const EdgeInsets.symmetric(vertical: 20),  
      child: Center(  
        child: Column(mainAxisSize: MainAxisSize.min, children: [  
          CircleAvatar(  
              radius: 28,  
              backgroundColor: cs.surfaceContainerHighest,  
              child: Icon(ic, color: cs.onSurfaceVariant)),  
          const SizedBox(height: 12),  
          Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),  
          const SizedBox(height: 4),  
          Text(sub,  
              textAlign: TextAlign.center,  
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),  
        ]),  
      ),  
    );  
  }  
  
  Widget txTile(Tx t) {  
    final cs = Theme.of(context).colorScheme;  
    final c = t.debit ? expenseColor : incomeColor;  
    return Padding(  
      padding: const EdgeInsets.symmetric(vertical: 10),  
      child: Row(children: [  
        Container(  
          width: 42,  
          height: 42,  
          decoration: BoxDecoration(  
              color: c.withOpacity(0.14),  
              borderRadius: BorderRadius.circular(14)),  
          child: Icon(  
              t.debit ? Icons.north_east_rounded : Icons.south_west_rounded,  
              color: c,  
              size: 20),  
        ),  
        const SizedBox(width: 12),  
        Expanded(  
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [  
            Text(t.to,  
                maxLines: 1,  
                overflow: TextOverflow.ellipsis,  
                style: const TextStyle(fontWeight: FontWeight.w600)),  
            const SizedBox(height: 2),  
            Text(  
                '${two(t.d.day)}/${two(t.d.month)}/${t.d.year}  ${two(t.d.hour)}:${two(t.d.minute)}  \u2022  A/c ${t.acc}',  
                maxLines: 1,  
                overflow: TextOverflow.ellipsis,  
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),  
          ]),  
        ),  
        const SizedBox(width: 8),  
        Text('${t.debit ? "-" : "+"}${money(t.amt, 2)}',  
            style: TextStyle(color: c, fontWeight: FontWeight.w700)),  
      ]),  
    );  
  }  
  
  Widget txList(List<Tx> l) => Column(children: [  
        for (var i = 0; i < l.length; i++) ...[  
          txTile(l[i]),  
          if (i != l.length - 1)  
            Divider(  
                height: 1,  
                color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),  
        ]  
      ]);  
  
  Widget statusView() => Center(  
        child: Padding(  
          padding: const EdgeInsets.all(24),  
          child: Column(mainAxisSize: MainAxisSize.min, children: [  
            Icon(Icons.sms_outlined,  
                size: 48, color: Theme.of(context).colorScheme.outline),  
            const SizedBox(height: 12),  
            Text(status, textAlign: TextAlign.center),  
            const SizedBox(height: 16),  
            FilledButton.tonalIcon(  
                onPressed: load,  
                icon: const Icon(Icons.refresh),  
                label: const Text('Refresh')),  
          ]),  
        ),  
      );  
  
  // ---------- build ----------  
  
  @override  
  Widget build(BuildContext context) {  
    final showStatus = status.isNotEmpty && all.isEmpty;  
    final pages = [homePage(), txPage(), reportsPage(), budgetPage()];  
    return Scaffold(  
      body: showStatus  
          ? SafeArea(child: statusView())  
          : IndexedStack(index: tab, children: pages),  
      floatingActionButton: FloatingActionButton.extended(  
        onPressed: addTx,  
        icon: const Icon(Icons.add),  
        label: const Text('Add'),  
      ),  
      bottomNavigationBar: NavigationBar(  
        selectedIndex: tab,  
        onDestinationSelected: (i) => setState(() => tab = i),  
        destinations: const [  
          NavigationDestination(  
              icon: Icon(Icons.home_outlined),  
              selectedIcon: Icon(Icons.home),  
              label: 'Home'),  
          NavigationDestination(  
              icon: Icon(Icons.receipt_long_outlined),  
              selectedIcon: Icon(Icons.receipt_long),  
              label: 'Transactions'),  
          NavigationDestination(  
              icon: Icon(Icons.bar_chart_outlined),  
              selectedIcon: Icon(Icons.bar_chart),  
              label: 'Reports'),  
          NavigationDestination(  
              icon: Icon(Icons.account_balance_wallet_outlined),  
              selectedIcon: Icon(Icons.account_balance_wallet),  
              label: 'Budget'),  
        ],  
      ),  
    );  
  }  
  
  // ---------- HOME TAB ----------  
  
  Widget homePage() {  
    final cs = Theme.of(context).colorScheme;  
    final now = DateTime.now();  
    final income = sumFor(now, false);  
    final spent = sumFor(now, true);  
    final bal = income - spent;  
    final over = spent > budget;  
    final pct = budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0);  
    final recent = all.take(6).toList();  
  
    Widget pill(String label, double v, IconData ic, Color c) => Expanded(  
          child: Container(  
            padding: const EdgeInsets.all(12),  
            decoration: BoxDecoration(  
                color: cs.onPrimary.withOpacity(0.14),  
                borderRadius: BorderRadius.circular(16)),  
            child: Row(children: [  
              CircleAvatar(  
                  radius: 15,  
                  backgroundColor: c,  
                  child: Icon(ic, size: 16, color: Colors.white)),  
              const SizedBox(width: 8),  
              Expanded(  
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [  
                  Text(label,  
                      style: TextStyle(  
                          color: cs.onPrimary.withOpacity(0.8), fontSize: 12)),  
                  FittedBox(  
                      fit: BoxFit.scaleDown,  
                      child: Text(money(v),  
                          style: TextStyle(  
                              color: cs.onPrimary, fontWeight: FontWeight.w700))),  
                ]),  
              ),  
            ]),  
          ),  
        );  
  
    return page([  
      Padding(  
        padding: const EdgeInsets.only(top: 8),  
        child: Row(children: [  
          Expanded(  
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [  
              Text('Mera Kharcha',  
                  style: Theme.of(context)  
                      .textTheme  
                      .headlineSmall  
                      ?.copyWith(fontWeight: FontWeight.w800)),  
              const SizedBox(height: 2),  
              Text(  
                  '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}',  
                  style: TextStyle(color: cs.onSurfaceVariant)),  
            ]),  
          ),  
          IconButton.filledTonal(  
              onPressed: load,  
              tooltip: 'Refresh',  
              icon: const Icon(Icons.refresh)),  
        ]),  
      ),  
      const SizedBox(height: 20),  
      Container(  
        padding: const EdgeInsets.all(20),  
        decoration: BoxDecoration(  
          gradient: LinearGradient(  
              begin: Alignment.topLeft,  
              end: Alignment.bottomRight,  
              colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.5)!]),  
          borderRadius: BorderRadius.circular(28),  
        ),  
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [  
          Row(children: [  
            Icon(Icons.account_balance_wallet_outlined,  
                size: 18, color: cs.onPrimary.withOpacity(0.8)),  
            const SizedBox(width: 8),  
            Text('${months[now.month - 1]} balance',  
                style: TextStyle(color: cs.onPrimary.withOpacity(0.8))),  
          ]),  
          const SizedBox(height: 8),  
          FittedBox(  
            fit: BoxFit.scaleDown,  
            child: Text(money(bal),  
                style: TextStyle(  
                    color: cs.onPrimary,  
                    fontSize: 36,  
                    fontWeight: FontWeight.w800)),  
          ),  
          const SizedBox(height: 20),  
          Row(children: [  
            pill('Income', income, Icons.south_west_rounded, incomeColor),  
            const SizedBox(width: 12),  
            pill('Expense', spent, Icons.north_east_rounded, expenseColor),  
          ]),  
        ]),  
      ),  
      const SizedBox(height: 16),  
      card(  
        onTap: () => setState(() => tab = 3),  
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [  
          Row(children: [  
            Icon(Icons.savings_outlined, size: 20, color: cs.primary),  
            const SizedBox(width: 8),  
            const Expanded(  
                child: Text('Monthly budget',  
                    style: TextStyle(fontWeight: FontWeight.w700))),  
            Text('${(pct * 100).toStringAsFixed(0)}%',  
                style: TextStyle(  
                    fontWeight: FontWeight.w800,  
                    color: over ? expenseColor : cs.primary)),  
          ]),  
          const SizedBox(height: 14),  
          ClipRRect(  
            borderRadius: BorderRadius.circular(8),  
            child: LinearProgressIndicator(  
                value: pct,  
                minHeight: 10,  
                color: over ? expenseColor : cs.primary,  
                backgroundColor: cs.surfaceContainerHighest),  
          ),  
          const SizedBox(height: 10),  
          Row(children: [  
            Expanded(  
              child: Text('${money(spent)} / ${money(budget)}',  
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),  
            ),  
            Text(  
                over  
                    ? 'Budget cross ho gaya!'  
                    : pct >= 0.8  
                        ? 'Limit ke paas'  
                        : 'Budget ke andar',  
                style: TextStyle(  
                    fontSize: 13,  
                    fontWeight: FontWeight.w600,  
                    color: over ? expenseColor : cs.onSurfaceVariant)),  
          ]),  
        ]),  
      ),  
      title('Recent transactions',  
          trailing: TextButton(  
              onPressed: () => setState(() => tab = 1),  
              child: const Text('See all'))),  
      card(  
        recent.isEmpty  
            ? empty(Icons.receipt_long_outlined, 'Abhi koi transaction nahi',  
                'Add button se pehla transaction jodein')  
            : txList(recent),  
        pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),  
      ),  
    ]);  
  }  
  
  // ---------- TRANSACTIONS TAB ----------  
  
  Widget txPage() {  
    final cs = Theme.of(context).colorScheme;  
    final l = all  
        .where((t) => filter == 0 || (filter == 1 ? !t.debit : t.debit))  
        .toList();  
    final groups = <String, List<Tx>>{};  
    for (final t in l) {  
      groups.putIfAbsent(dayLabel(t.d), () => []).add(t);  
    }  
    Widget chip(String label, int v) => Padding(  
          padding: const EdgeInsets.only(right: 8),  
          child: ChoiceChip(  
            label: Text(label),  
            selected: filter == v,  
            onSelected: (_) => setState(() => filter = v),  
          ),  
        );  
  
    return page([  
      title('Transactions',  
          trailing: Text('${l.length} total',  
              style: TextStyle(color: cs.onSurfaceVariant))),  
      SingleChildScrollView(  
        scrollDirection: Axis.horizontal,  
        child: Row(children: [chip('All', 0), chip('Income', 1), chip('Expense', 2)]),  
      ),  
      const SizedBox(height: 8),  
      if (l.isEmpty)  
        card(empty(Icons.search_off_rounded, 'Koi transaction nahi mila',  
            'Filter badal kar dekhein'))  
      else  
        for (final e in groups.entries) ...[  
          Padding(  
            padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),  
            child: Text(e.key,  
                style: TextStyle(  
                    fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),  
          ),  
          card(txList(e.value),  
              pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 4)),  
        ],  
    ]);  
  }  
  
  // ---------- REPORTS TAB ----------  
  
  Widget reportsPage() {  
    final cs = Theme.of(context).colorScheme;  
    final now = DateTime.now();  
    final ms = List.generate(6, (i) => DateTime(now.year, now.month - 5 + i));  
    final monthly = ms.map((m) => sumFor(m, true)).toList();  
    final monthlyInc = ms.map((m) => sumFor(m, false)).toList();  
    final byAcc = <String, double>{};  
    for (final t in all.where((t) => t.debit)) {  
      byAcc[t.acc] = (byAcc[t.acc] ?? 0) + t.amt;  
    }  
    final accs = byAcc.entries.toList();  
    final accTotal = accs.fold<double>(0, (s, e) => s + e.value);  
    final colors = [  
      cs.primary, cs.tertiary, cs.secondary,  
      cs.primary.withOpacity(0.5), cs.tertiary.withOpacity(0.5),  
      cs.secondary.withOpacity(0.5)  
    ];  
    final maxV = [...monthly, ...monthlyInc].fold<double>(1, (a, b) => b > a ? b : a);  
    final maxExp = monthly.fold<double>(1, (a, b) => b > a ? b : a);  
    final total6 = monthly.fold<double>(0, (a, b) => a + b);  
    final hasExp = total6 > 0;  
  
    Widget bar(double v, Color c) => Row(children: [  
          Expanded(  
            child: ClipRRect(  
              borderRadius: BorderRadius.circular(4),  
              child: LinearProgressIndicator(  
                  value: v / maxV,  
                  minHeight: 6,  
                  color: c,  
                  backgroundColor: cs.surfaceContainerHighest),  
            ),  
          ),  
          SizedBox(  
            width: 76,  
            child: Text(money(v),  
                textAlign: TextAlign.right,  
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),  
          ),  
        ]);  
  
    return page([  
      title('Reports'),  
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [  
        const Text('Monthly kharcha (6 mahine)',  
            style: TextStyle(fontWeight: FontWeight.w700)),  
        const SizedBox(height: 4),  
        Text('Kul ${money(total6)}  \u2022  Average ${money(total6 / 6)} / mahina',  
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),  
        const SizedBox(height: 16),  
        if (!hasExp)  
          empty(Icons.bar_chart_rounded, 'Abhi koi kharcha nahi',  
              'Expense jodte hi chart yahan dikhega')  
        else  
          SizedBox(  
            height: 200,  
            child: BarChart(BarChartData(  
              maxY: maxExp * 1.2,  
              gridData: const FlGridData(show: false),  
              borderData: FlBorderData(show: false),  
              barTouchData: BarTouchData(  
                touchTooltipData: BarTouchTooltipData(  
                  getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(  
                      money(rod.toY),  
                      const TextStyle(  
                          color: Colors.white, fontWeight: FontWeight.w600)),  
                ),  
              ),  
              barGroups: [  
                for (var i = 0; i < 6; i++)  
                  BarChartGroupData(x: i, barRods: [  
                    BarChartRodData(  
                        toY: monthly[i],  
                        color: i == 5 ? cs.primary : cs.primary.withOpacity(0.35),  
                        width: 22,  
                        borderRadius: BorderRadius.circular(8),  
                        backDrawRodData: BackgroundBarChartRodData(  
                            show: true,  
                            toY: maxExp * 1.2,  
                            color: cs.surfaceContainerHighest.withOpacity(0.5)))  
                  ])  
              ],  
              titlesData: FlTitlesData(  
                topTitles: const AxisTitles(),  
                rightTitles: const AxisTitles(),  
                leftTitles: const AxisTitles(),  
                bottomTitles: AxisTitles(  
                    sideTitles: SideTitles(  
                        showTitles: true,  
                        getTitlesWidget: (v, _) => Padding(  
                              padding: const EdgeInsets.only(top: 6),  
                              child: Text(  
                                  '${ms[v.toInt()].month}/${ms[v.toInt()].year % 100}',  
                                  style: TextStyle(  
                                      fontSize: 11, color: cs.onSurfaceVariant)),  
                            ))),  
              ),  
            )),  
          ),  
      ])),  
      const SizedBox(height: 16),  
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [  
        const Text('Account-wise kharcha',  
            style: TextStyle(fontWeight: FontWeight.w700)),  
        const SizedBox(height: 12),  
        if (accs.isEmpty)  
          empty(Icons.pie_chart_outline_rounded, 'Abhi koi kharcha nahi',  
              'Account-wise breakdown yahan dikhega')  
        else ...[  
          SizedBox(  
            height: 190,  
            child: Stack(alignment: Alignment.center, children: [  
              PieChart(PieChartData(  
                  sectionsSpace: 3,  
                  centerSpaceRadius: 58,  
                  sections: [  
                    for (var i = 0; i < accs.length; i++)  
                      PieChartSectionData(  
                          value: accs[i].value,  
                          title: '',  
                          radius: 26,  
                          color: colors[i % colors.length])  
                  ])),  
              Column(mainAxisSize: MainAxisSize.min, children: [  
                Text('Total', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),  
                Text(money(accTotal),  
                    style: const TextStyle(fontWeight: FontWeight.w800)),  
              ]),  
            ]),  
          ),  
          const SizedBox(height: 12),  
          for (var i = 0; i < accs.length; i++)  
            Padding(  
              padding: const EdgeInsets.symmetric(vertical: 5),  
              child: Row(children: [  
                Container(  
                    width: 12,  
                    height: 12,  
                    decoration: BoxDecoration(  
                        color: colors[i % colors.length],  
                        borderRadius: BorderRadius.circular(4))),  
                const SizedBox(width: 10),  
                Expanded(child: Text('A/c ${accs[i].key}')),  
                Text(money(accs[i].value),  
                    style: const TextStyle(fontWeight: FontWeight.w600)),  
                SizedBox(  
                  width: 48,  
                  child: Text(  
                      '${(accs[i].value / accTotal * 100).toStringAsFixed(0)}%',  
                      textAlign: TextAlign.right,  
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),  
                ),  
              ]),  
            ),  
        ],  
      ])),  
      const SizedBox(height: 16),  
      card(Row(children: [  
        CircleAvatar(  
            backgroundColor: cs.surfaceContainerHighest,  
            child: Icon(Icons.category_outlined, color: cs.onSurfaceVariant)),  
        const SizedBox(width: 12),  
        Expanded(  
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [  
            const Text('Category-wise kharcha',  
                style: TextStyle(fontWeight: FontWeight.w700)),  
            const SizedBox(height: 2),  
            Text('Jaldi aa raha hai \u2013 food, travel, bills jaisi categories yahan dikhengi.',  
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),  
          ]),  
        ),  
      ])),  
      title('Last 6 months comparison'),  
      card(Column(children: [  
        Row(children: [  
          const CircleAvatar(radius: 5, backgroundColor: incomeColor),  
          const SizedBox(width: 6),  
          const Text('Income', style: TextStyle(fontSize: 12)),  
          const SizedBox(width: 16),  
          const CircleAvatar(radius: 5, backgroundColor: expenseColor),  
          const SizedBox(width: 6),  
          const Text('Expense', style: TextStyle(fontSize: 12)),  
        ]),  
        const SizedBox(height: 8),  
        for (var i = 5; i >= 0; i--) ...[  
          Padding(  
            padding: const EdgeInsets.symmetric(vertical: 10),  
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [  
              Row(children: [  
                Expanded(  
                    child: Text(  
                        '${months[ms[i].month - 1].substring(0, 3)} ${ms[i].year}',  
                        style: const TextStyle(fontWeight: FontWeight.w700))),  
                Text(  
                    'Net ${monthlyInc[i] - monthly[i] < 0 ? "-" : "+"}${money((monthlyInc[i] - monthly[i]).abs())}',  
                    style: TextStyle(  
                        fontSize: 12,  
                        fontWeight: FontWeight.w600,  
                        color: monthlyInc[i] - monthly[i] < 0  
                            ? expenseColor  
                            : incomeColor)),  
              ]),  
              const SizedBox(height: 8),  
              bar(monthlyInc[i], incomeColor),  
              const SizedBox(height: 6),  
              bar(monthly[i], expenseColor),  
            ]),  
          ),  
          if (i != 0)  
            Divider(height: 1, color: cs.outlineVariant.withOpacity(0.5)),  
        ],  
      ])),  
    ]);  
  }  
  
  // ---------- BUDGET TAB ----------  
  
  Widget budgetPage() {  
    final cs = Theme.of(context).colorScheme;  
    final spent = sumFor(DateTime.now(), true);  
    final over = spent > budget;  
    final remaining = budget - spent;  
    final pct = budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0);  
    final c = over ? expenseColor : cs.primary;  
  
    Widget tile(String l, double v, Color? vc) => Expanded(  
          child: Container(  
            padding: const EdgeInsets.all(12),  
            decoration: BoxDecoration(  
                color: cs.surfaceContainerHighest.withOpacity(0.5),  
                borderRadius: BorderRadius.circular(16)),  
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [  
              Text(l, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),  
              const SizedBox(height: 4),  
              FittedBox(  
                fit: BoxFit.scaleDown,  
                child: Text(money(v),  
                    style: TextStyle(  
                        fontSize: 16, fontWeight: FontWeight.w800, color: vc)),  
              ),  
            ]),  
          ),  
        );  
  
    return page([  
      title('Budget',  
          trailing: FilledButton.tonalIcon(  
              onPressed: editBudget,  
              icon: const Icon(Icons.edit, size: 18),  
              label: const Text('Edit'))),  
      if (over)  
        Container(  
          margin: const EdgeInsets.only(bottom: 12),  
          padding: const EdgeInsets.all(14),  
          decoration: BoxDecoration(  
              color: expenseColor.withOpacity(0.14),  
              borderRadius: BorderRadius.circular(16),  
              border: Border.all(color: expenseColor.withOpacity(0.5))),  
          child: Row(children: [  
            const Icon(Icons.warning_amber_rounded, color: expenseColor),  
            const SizedBox(width: 10),  
            Expanded(  
                child: Text(  
                    'Budget cross ho gaya! Aap ${money(remaining.abs())} zyada kharch kar chuke hain.',  
                    style: const TextStyle(fontWeight: FontWeight.w600))),  
          ]),  
        )  
      else if (pct >= 0.8)  
        Container(  
          margin: const EdgeInsets.only(bottom: 12),  
          padding: const EdgeInsets.all(14),  
          decoration: BoxDecoration(  
              color: cs.tertiaryContainer,  
              borderRadius: BorderRadius.circular(16)),  
          child: Row(children: [  
            Icon(Icons.info_outline_rounded, color: cs.onTertiaryContainer),  
            const SizedBox(width: 10),  
            Expanded(  
                child: Text('Budget ka ${(pct * 100).toStringAsFixed(0)}% use ho chuka hai.',  
                    style: TextStyle(  
                        color: cs.onTertiaryContainer,  
                        fontWeight: FontWeight.w600))),  
          ]),  
        ),  
      card(  
        pad: const EdgeInsets.all(20),  
        Column(children: [  
          const SizedBox(height: 8),  
          SizedBox(  
            width: 190,  
            height: 190,  
            child: Stack(alignment: Alignment.center, children: [  
              SizedBox.expand(  
                child: CircularProgressIndicator(  
                    value: pct,  
                    strokeWidth: 14,  
                    strokeCap: StrokeCap.round,  
                    color: c,  
                    backgroundColor: cs.surfaceContainerHighest),  
              ),  
              Padding(  
                padding: const EdgeInsets.symmetric(horizontal: 30),  
                child: Column(mainAxisSize: MainAxisSize.min, children: [  
                  Text(over ? 'Over by' : 'Remaining',  
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),  
                  FittedBox(  
                    fit: BoxFit.scaleDown,  
                    child: Text(money(remaining.abs()),  
                        style: TextStyle(  
                            fontSize: 28, fontWeight: FontWeight.w800, color: c)),  
                  ),  
                  Text('${(pct * 100).toStringAsFixed(0)}% used',  
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),  
                ]),  
              ),  
            ]),  
          ),  
          const SizedBox(height: 24),  
          Row(children: [  
            tile('Budget', budget, null),  
            const SizedBox(width: 8),  
            tile('Spent', spent, expenseColor),  
            const SizedBox(width: 8),  
            tile(over ? 'Over' : 'Remaining', remaining.abs(),  
                over ? expenseColor : incomeColor),  
          ]),  
        ]),  
      ),  
    ]);  
  }  
  
  // ---------- DIALOGS ----------  
  
  void editBudget() {  
    final c = TextEditingController(text: budget.toStringAsFixed(0));  
    showDialog(  
        context: context,  
        builder: (_) => AlertDialog(  
              title: const Text('Monthly budget'),  
              content: TextField(  
                controller: c,  
                autofocus: true,  
                keyboardType: TextInputType.number,  
                decoration: InputDecoration(  
                    prefixText: '$rs ',  
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),  
              ),  
              actions: [  
                TextButton(  
                    onPressed: () {  
                      setState(() => budget = double.tryParse(c.text) ?? budget);  
                      Navigator.pop(context);  
                    },  
                    child: const Text('Save'))  
              ],  
            ));  
  }  
  
  void addTx() {  
    final amtC = TextEditingController();  
    final toC = TextEditingController();  
    final accC = TextEditingController();  
    var debit = true;  
    String? err;  
    InputDecoration deco(String l, IconData ic) => InputDecoration(  
        labelText: l,  
        prefixIcon: Icon(ic),  
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)));  
  
    showModalBottomSheet(  
      context: context,  
      isScrollControlled: true,  
      showDragHandle: true,  
      builder: (ctx) => StatefulBuilder(  
        builder: (ctx, setS) {  
          final cs = Theme.of(ctx).colorScheme;  
          Widget type(String label, bool isDebit, IconData ic, Color col) {  
            final sel = debit == isDebit;  
            return Expanded(  
              child: InkWell(  
                borderRadius: BorderRadius.circular(16),  
                onTap: () => setS(() => debit = isDebit),  
                child: AnimatedContainer(  
                  duration: const Duration(milliseconds: 150),  
                  padding: const EdgeInsets.symmetric(vertical: 14),  
                  decoration: BoxDecoration(  
                      color: sel ? col.withOpacity(0.16) : Colors.transparent,  
                      borderRadius: BorderRadius.circular(16),  
                      border: Border.all(  
                          color: sel ? col : cs.outlineVariant, width: sel ? 1.5 : 1)),  
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [  
                    Icon(ic, color: sel ? col : cs.onSurfaceVariant, size: 20),  
                    const SizedBox(width: 8),  
                    Text(label,  
                        style: TextStyle(  
                            fontWeight: FontWeight.w700,  
                            color: sel ? col : cs.onSurfaceVariant)),  
                  ]),  
                ),  
              ),  
            );  
          }  
  
          return Padding(  
            padding: EdgeInsets.fromLTRB(  
                20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),  
            child: SingleChildScrollView(  
              child: Column(mainAxisSize: MainAxisSize.min, children: [  
                Text('Add transaction',  
                    style: Theme.of(ctx)  
                        .textTheme  
                        .titleLarge  
                        ?.copyWith(fontWeight: FontWeight.w800)),  
                const SizedBox(height: 16),  
                Row(children: [  
                  type('Expense', true, Icons.north_east_rounded, expenseColor),  
                  const SizedBox(width: 12),  
                  type('Income', false, Icons.south_west_rounded, incomeColor),  
                ]),  
                const SizedBox(height: 16),  
                TextField(  
                  controller: amtC,  
                  autofocus: true,  
                  textAlign: TextAlign.center,  
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),  
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),  
                  decoration: InputDecoration(  
                      hintText: '0',  
                      prefixText: '$rs ',  
                      errorText: err,  
                      filled: true,  
                      fillColor: cs.surfaceContainerHighest.withOpacity(0.5),  
                      border: OutlineInputBorder(  
                          borderRadius: BorderRadius.circular(18),  
                          borderSide: BorderSide.none)),  
                ),  
                const SizedBox(height: 12),  
                TextField(  
                    controller: toC,  
                    textCapitalization: TextCapitalization.sentences,  
                    decoration: deco('Description (e.g. Grocery)', Icons.notes_rounded)),  
                const SizedBox(height: 12),  
                TextField(  
                    controller: accC,  
                    keyboardType: TextInputType.number,  
                    maxLength: 4,  
                    decoration: deco('Account last digits (optional)',  
                        Icons.account_balance_outlined)),  
                const SizedBox(height: 4),  
                SizedBox(  
                  width: double.infinity,  
                  height: 52,  
                  child: FilledButton(  
                    onPressed: () {  
                      final a = double.tryParse(amtC.text.replaceAll(',', ''));  
                      if (a == null || a <= 0) {  
                        setS(() => err = 'Sahi amount daalein');  
                        return;  
                      }  
                      setState(() => manual.add(Tx(  
                          DateTime.now(),  
                          a,  
                          accC.text.trim().isEmpty ? 'Cash' : 'XX${accC.text.trim()}',  
                          toC.text.trim().isEmpty ? '-' : toC.text.trim(),  
                          debit)));  
                      Navigator.pop(ctx);  
                      ScaffoldMessenger.of(context).showSnackBar(  
                          const SnackBar(content: Text('Transaction save ho gaya')));  
                    },  
                    child: const Text('Save transaction',  
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),  
                  ),  
                ),  
              ]),  
            ),  
          );  
        },  
      ),  
    );  
  }  
}  
