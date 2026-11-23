import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});
  @override Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final width = constraints.maxWidth > 620 ? 560.0 : constraints.maxWidth;
    return Align(alignment: Alignment.topCenter, child: SizedBox(width: width, child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: children.map((w) => Padding(padding: const EdgeInsets.only(bottom: 9), child: w)).toList(),
    )));
  });
}

class ScreenHeading extends StatelessWidget {
  final String title; final String? detail; final String? eyebrow;
  const ScreenHeading({super.key, required this.title, this.detail, this.eyebrow});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 7), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (eyebrow != null) Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(eyebrow!, style: tinyCaps)),
    Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -.6, color: ink)),
    if (detail != null) Padding(padding: const EdgeInsets.only(top: 5), child: Text(detail!, style: const TextStyle(fontSize: 11, color: muted))),
  ]));
}

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 8, bottom: 5), child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink)));
}

class SectionHeading extends StatelessWidget {
  final String title; final String? action;
  const SectionHeading(this.title, {super.key, this.action});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 8, bottom: 1), child: Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink))), if (action != null) Text(action!, style: const TextStyle(fontSize: 9, color: muted, decoration: TextDecoration.underline))]));
}

class InfoCard extends StatelessWidget {
  final Widget child;
  const InfoCard({super.key, required this.child});
  @override Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: card, border: Border.all(color: line), borderRadius: BorderRadius.circular(6)), child: child);
}

class BadgeX extends StatelessWidget {
  final String text; final bool dark; final bool danger;
  const BadgeX(this.text, {super.key, this.dark = false, this.danger = false});
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: dark ? ink : danger ? const Color(0xFFE2E2DE) : const Color(0xFFF4F4F1), border: Border.all(color: dark ? ink : danger ? const Color(0xFF999C98) : const Color(0xFFC4C6C2)), borderRadius: BorderRadius.circular(3)), child: Text(text.toUpperCase(), style: TextStyle(fontSize: 8, letterSpacing: .2, fontWeight: FontWeight.w700, color: dark ? Colors.white : ink)));
}

class ProgressBar extends StatelessWidget {
  final double value;
  const ProgressBar({super.key, required this.value});
  @override Widget build(BuildContext context) => ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: value, minHeight: 5, backgroundColor: const Color(0xFFDEDFDB), color: const Color(0xFF454846)));
}

class StatTile extends StatelessWidget {
  final String number, label; final bool highlighted;
  const StatTile(this.number, this.label, {super.key, this.highlighted = false});
  @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(right: 4), padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3), decoration: BoxDecoration(color: highlighted ? const Color(0xFFE6E6E2) : card, border: Border.all(color: line)), child: Column(children: [Text(number, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)), Text(label, style: const TextStyle(fontSize: 8, color: muted))]));
}

class MetricsRow extends StatelessWidget {
  final List<(String,String)> items;
  const MetricsRow({super.key, required this.items});
  @override Widget build(BuildContext context) => Row(children: items.map((e) => Expanded(child: Column(children: [Text(e.$1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)), Text(e.$2, style: const TextStyle(fontSize: 8, color: muted))]))).toList());
}

class DataRowTile extends StatelessWidget {
  final String title; final String? subtitle, leading, trailing; final IconData? icon;
  const DataRowTile({super.key, required this.title, this.subtitle, this.leading, this.trailing, this.icon});
  @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 5), padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8), decoration: BoxDecoration(color: const Color(0xFFFBFBF8), border: Border.all(color: const Color(0xFFD1D2CF)), borderRadius: BorderRadius.circular(5)), child: Row(children: [
    if (leading != null) Container(width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFEDEDE9), border: Border.all(color: line), shape: BoxShape.circle), child: Text(leading!, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700))),
    if (icon != null) Container(width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFEDEDE9), border: Border.all(color: line), borderRadius: BorderRadius.circular(4)), child: Icon(icon, size: 16)),
    if (leading != null || icon != null) const SizedBox(width: 8),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8, color: muted)))])),
    if (trailing != null) Text(trailing!, style: const TextStyle(fontSize: 9, color: muted, fontWeight: FontWeight.w600)) else const Icon(Icons.chevron_right, size: 18, color: muted),
  ]));
}

class PrimaryButton extends StatelessWidget {
  final String label; final VoidCallback onPressed;
  const PrimaryButton({super.key, required this.label, required this.onPressed});
  @override Widget build(BuildContext context) => SizedBox(height: 39, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: ink, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)), textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), onPressed: onPressed, child: Text(label)));
}

class OutlineButtonX extends StatelessWidget {
  final String label; final VoidCallback onPressed;
  const OutlineButtonX({super.key, required this.label, required this.onPressed});
  @override Widget build(BuildContext context) => SizedBox(height: 39, child: OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: ink, side: const BorderSide(color: Color(0xFFAAADA9)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)), textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)), onPressed: onPressed, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)));
}

class SearchField extends StatelessWidget {
  final String hint;
  const SearchField({super.key, required this.hint});
  @override Widget build(BuildContext context) => TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: hint, contentPadding: const EdgeInsets.symmetric(vertical: 9), isDense: true));
}

class ChoiceChipsX extends StatelessWidget {
  final List<String> values; final String selected; final ValueChanged<String> onSelect;
  const ChoiceChipsX({super.key, required this.values, required this.selected, required this.onSelect});
  @override Widget build(BuildContext context) => Wrap(spacing: 5, runSpacing: 5, children: values.map((v) => ChoiceChip(label: Text(v, style: const TextStyle(fontSize: 9)), selected: selected == v, onSelected: (_) => onSelect(v), showCheckmark: false, padding: const EdgeInsets.symmetric(horizontal: 4), visualDensity: VisualDensity.compact, side: BorderSide(color: selected == v ? ink : line), selectedColor: const Color(0xFFE1E2DE), backgroundColor: paper)).toList());
}

class TimelineEntry extends StatelessWidget {
  final String title, subtitle; final String? state, tag;
  const TimelineEntry(this.title, this.subtitle, {super.key, this.state, this.tag});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [Container(width: 23, height: 23, decoration: BoxDecoration(shape: BoxShape.circle, color: state == 'done' ? ink : paper, border: Border.all(color: state == 'done' ? ink : const Color(0xFF9A9D99))), child: Icon(state == 'done' ? Icons.check : state == 'late' ? Icons.priority_high : Icons.circle, size: 11, color: state == 'done' ? Colors.white : muted)), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), Text(subtitle, style: const TextStyle(fontSize: 8, color: muted))])), if (tag != null) BadgeX(tag!, danger: state == 'late', dark: state == 'active')]));
}

class DropdownField extends StatelessWidget {
  final List<String> items;
  const DropdownField({super.key, required this.items});
  @override Widget build(BuildContext context) => DropdownButtonFormField<String>(initialValue: items.first, items: items.map((x) => DropdownMenuItem(value: x, child: Text(x, style: const TextStyle(fontSize: 11)))).toList(), onChanged: (_) {}, decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)));
}

class AttachmentTile extends StatelessWidget {
  final String label;
  const AttachmentTile({super.key, required this.label});
  @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.symmetric(vertical: 7), padding: const EdgeInsets.all(11), decoration: BoxDecoration(border: Border.all(color: line), borderRadius: BorderRadius.circular(5)), child: Row(children: [const Icon(Icons.attach_file, size: 17), const SizedBox(width: 7), Text(label, style: const TextStyle(fontSize: 10, color: muted))]));
}

class CheckLine extends StatelessWidget {
  final String text; final bool checked; final String? tag;
  const CheckLine(this.text, {super.key, this.checked = false, this.tag});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [Icon(checked ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: ink), const SizedBox(width: 7), Expanded(child: Text(text, style: const TextStyle(fontSize: 10))), if (tag != null) BadgeX(tag!, dark: tag == 'ACTIVE')]));
}

class QuickAction extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const QuickAction({super.key, required this.icon, required this.label, required this.onTap});
  @override Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 3),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F2), border: Border.all(color: line), borderRadius: BorderRadius.circular(5)),
      child: Column(children: [Icon(icon, size: 18), const SizedBox(height: 5), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700))]),
    ),
  );
}

class QuickTile extends StatelessWidget {
  final IconData icon; final String title, subtitle;
  const QuickTile({super.key, required this.icon, required this.title, required this.subtitle});
  @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(right: 5), padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4), decoration: BoxDecoration(color: card, border: Border.all(color: line), borderRadius: BorderRadius.circular(5)), child: Column(children: [Icon(icon, size: 17), const SizedBox(height: 6), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700)), Text(subtitle, style: const TextStyle(fontSize: 7, color: muted))]));
}

class DeadlineCard extends StatelessWidget {
  final String day, label, title, subtitle; final bool urgent;
  const DeadlineCard({super.key, required this.day, required this.label, required this.title, required this.subtitle, this.urgent = false});
  @override Widget build(BuildContext context) => InfoCard(child: Row(children: [Container(width: 43, padding: const EdgeInsets.symmetric(vertical: 7), decoration: const BoxDecoration(color: Color(0xFFE8E8E4)), child: Column(children: [Text(day, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const Text('OCT', style: TextStyle(fontSize: 8, color: muted))])), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [BadgeX(label, danger: urgent), const SizedBox(height: 5), Text(title, style: titleStyle), Text(subtitle, style: subStyle)])), const Icon(Icons.chevron_right, color: muted)]));
}

class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key});
  @override Widget build(BuildContext context) => SizedBox(width: 68, height: 68, child: Stack(alignment: Alignment.center, children: [const SizedBox.expand(child: CircularProgressIndicator(value: .72, strokeWidth: 6, backgroundColor: Color(0xFFDEDFDB), color: ink)), const Text('72%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))]));
}

class NotificationTile extends StatelessWidget {
  final IconData icon; final String title, message, time; final bool unread;
  const NotificationTile({super.key, required this.icon, required this.title, required this.message, required this.time, this.unread = false});
  @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: unread ? const Color(0xFFEDEDE9) : card, border: Border.all(color: line), borderRadius: BorderRadius.circular(5)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 31, height: 31, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFE1E2DE), borderRadius: BorderRadius.circular(5)), child: Icon(icon, size: 17)), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(message, style: const TextStyle(fontSize: 9, color: muted)), const SizedBox(height: 5), Text(time, style: const TextStyle(fontSize: 8, color: muted))])), if (unread) const Icon(Icons.circle, size: 7, color: ink)]));
}

class SwitchTile extends StatefulWidget {
  final String title, subtitle; final Widget? trailing;
  const SwitchTile({super.key, required this.title, required this.subtitle, this.trailing});
  @override State<SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends State<SwitchTile> {
  bool enabled = true;
  @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 5), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: card, border: Border.all(color: line), borderRadius: BorderRadius.circular(5)), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), Text(widget.subtitle, style: const TextStyle(fontSize: 8, color: muted))])), widget.trailing ?? Switch(value: enabled, onChanged: (v) => setState(() => enabled = v), activeThumbColor: ink)]));
}

class DetailLine extends StatelessWidget {
  final String label, value;
  const DetailLine(this.label, this.value, {super.key});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [Expanded(child: Text(label, style: subStyle)), Text(value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700))]));
}

const titleStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink);
const subStyle = TextStyle(fontSize: 9, color: muted, height: 1.35);
const tinyCaps = TextStyle(fontSize: 8, color: muted, letterSpacing: 1, fontWeight: FontWeight.w700);
