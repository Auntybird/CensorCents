/// Aggregate count of how many AI-judged entries came back "approved"
/// (grudging praise / income) vs "disappointed" (scolded, or any
/// edit/delete correction roast). Only entries that have actually received
/// a verdict are counted — anything still "Awaiting judgement" is excluded.
class AiVerdictStats {
  final int approvedCount;
  final int disappointedCount;

  const AiVerdictStats({
    required this.approvedCount,
    required this.disappointedCount,
  });

  int get total => approvedCount + disappointedCount;
  double get approvedPercent => total == 0 ? 0 : approvedCount / total * 100;
  double get disappointedPercent => total == 0 ? 0 : disappointedCount / total * 100;
}