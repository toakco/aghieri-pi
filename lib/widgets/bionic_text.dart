import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// BionicText — renders text with the first N characters of each word bolded.
///
/// Based on Bionic Reading®: bold "fixation points" anchor the eye at the
/// start of each word, reducing the cognitive load of reading for people with
/// ADHD or dyslexia.
///
/// [fixation] controls how aggressively words are bolded (1 = lightest, 5 = heaviest).
/// F3 is the standard default used in published Bionic Reading research.
///
/// Fixation percentages per level:
///   F1 → ~20%   F2 → ~33%   F3 → ~45%   F4 → ~60%   F5 → ~80%
class BionicText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  /// 1 = lightest (fewest chars bolded) … 5 = heaviest (most chars bolded).
  final int fixation;

  const BionicText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.fixation = 3,
  });

  // ── Fixation length lookup ───────────────────────────────────────────────
  static const _fixationPct = [0.0, 0.20, 0.33, 0.45, 0.60, 0.80];

  /// Returns how many leading characters of [wordLen] to bold at [level].
  static int _fixLen(int wordLen, int level) {
    if (wordLen <= 0) return 0;
    if (wordLen == 1) return 1;
    final p = _fixationPct[level.clamp(1, 5)];
    // Always bold at least 1 char; never exceed the word length
    return (wordLen * p).ceil().clamp(1, wordLen);
  }

  // ── Token splitter ───────────────────────────────────────────────────────
  /// Splits [word] into (boldPart, lightPart).
  /// Trailing punctuation (.,!?;:'"—…) stays with the light portion.
  static (String bold, String light) _split(String word, int level) {
    if (word.isEmpty) return ('', '');

    // Separate leading/trailing punctuation so we only measure the letters
    final leadPunct = RegExp(r'^[^\w]+');
    final trailPunct = RegExp(r'[^\w]+$');
    final leading  = leadPunct.firstMatch(word)?.group(0) ?? '';
    final trailing = trailPunct.firstMatch(word)?.group(0) ?? '';
    final core = word.substring(leading.length,
        word.length - trailing.length);

    if (core.isEmpty) return (word, ''); // all punctuation

    final boldLen = _fixLen(core.length, level);
    final boldCore  = core.substring(0, boldLen);
    final lightCore = core.substring(boldLen);

    return ('$leading$boldCore', '$lightCore$trailing');
  }

  @override
  Widget build(BuildContext context) {
    final base = style ??
        AghieriTextStyles.body(size: 16, color: AghieriColors.textPrimary);

    final boldStyle  = base.copyWith(fontWeight: FontWeight.w700);
    final lightStyle = base.copyWith(fontWeight: FontWeight.w400);

    final spans = <TextSpan>[];
    // Match runs of non-whitespace (words) and whitespace (spaces/newlines)
    final re = RegExp(r'\S+|\s+');
    for (final m in re.allMatches(text)) {
      final token = m.group(0)!;
      if (token.trim().isEmpty) {
        spans.add(TextSpan(text: token, style: base));
      } else {
        final (bold, light) = _split(token, fixation);
        if (bold.isNotEmpty) spans.add(TextSpan(text: bold,  style: boldStyle));
        if (light.isNotEmpty) spans.add(TextSpan(text: light, style: lightStyle));
      }
    }

    return RichText(
      text: TextSpan(children: spans),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
