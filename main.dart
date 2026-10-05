import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';
import 'package:fl_chart/fl_chart.dart';

void main() => runApp(const MaterialApp(
    debugShowCheckedModeBanner: false, home: Home()));

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
  final a = RegExp(r'(?:rs\.?|inr|â‚¹)\s*([\d,]+(?:\.\d+)?)', caseSensitive: false)
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

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<Tx> txs = [];
  String status = 'Loading...';
  double budget = 10000;

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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final spent = txs
        .where((t) => t.debit && t.d.year == now.year && t.d.month == now.month)
        .fold<double>(0, (s, t) => s + t.amt);
    final over = spent > budget;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mera Kharcha'),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: load)],
          bottom: const TabBar(tabs: [Tab(text: 'Transactions'), Tab(text: 'Graphs')]),
        ),
        body: status.isNotEmpty
            ? Center(child: Text(status))
            : TabBarView(children: [list(), graphs(spent, over)]),
      ),
    );
  }

  Widget list() => ListView.separated(
        itemCount: txs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final t = txs[i];
          return ListTile(
            leading: Icon(t.debit ? Icons.arrow_upward : Icons.arrow_downward,
                color: t.debit ? Colors.red : Colors.green),
            title: Text('${t.debit ? "-" : "+"}â‚¹${t.amt.toStringAsFixed(2)}  ${t.to}'),
            subtitle: Text(
                '${two(t.d.day)}/${two(t.d.month)}/${t.d.year}  ${two(t.d.hour)}:${two(t.d.minute)}  |  A/c ${t.acc}'),
          );
        },
      );

  Widget graphs(double spent, bool over) {
    final now = DateTime.now();
    final months = List.generate(6, (i) => DateTime(now.year, now.month - 5 + i));
    final monthly = months
        .map((m) => txs
            .where((t) => t.debit && t.d.year == m.year && t.d.month == m.month)
            .fold<double>(0, (s, t) => s + t.amt))
        .toList();
    final byAcc = <String, double>{};
    for (final t in txs.where((t) => t.debit)) {
      byAcc[t.acc] = (byAcc[t.acc] ?? 0) + t.amt;
    }
    final colors = [Colors.blue, Colors.orange, Colors.green, Colors.purple, Colors.red, Colors.teal];
    var ci = 0;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        color: over ? Colors.red.shade100 : Colors.green.shade100,
        child: ListTile(
          title: Text('Is mahine: â‚¹${spent.toStringAsFixed(0)} / â‚¹${budget.toStringAsFixed(0)}'),
          subtitle: Text(over ? 'Budget cross ho gaya!' : 'Budget ke andar'),
          trailing: IconButton(icon: const Icon(Icons.edit), onPressed: editBudget),
        ),
      ),
      const SizedBox(height: 16),
      const Text('Monthly kharcha (6 mahine)', style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(
        height: 220,
        child: BarChart(BarChartData(
          barGroups: [
            for (var i = 0; i < 6; i++)
              BarChartGroupData(x: i, barRods: [BarChartRodData(toY: monthly[i], color: Colors.blue, width: 18)])
          ],
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) => Text('${months[v.toInt()].month}/${months[v.toInt()].year % 100}',
                        style: const TextStyle(fontSize: 11)))),
          ),
        )),
      ),
      const SizedBox(height: 24),
      const Text('Account-wise kharcha', style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(
        height: 220,
        child: PieChart(PieChartData(sections: [
          for (final e in byAcc.entries)
            PieChartSectionData(
                value: e.value,
                title: '${e.key}\nâ‚¹${e.value.toStringAsFixed(0)}',
                radius: 70,
                titleStyle: const TextStyle(fontSize: 10, color: Colors.white),
                color: colors[ci++ % colors.length])
        ])),
      ),
    ]);
  }

  void editBudget() {
    final c = TextEditingController(text: budget.toStringAsFixed(0));
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Monthly budget'),
              content: TextField(controller: c, keyboardType: TextInputType.number),
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
}
