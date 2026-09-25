// Spike S9 — worker cooperativo no web (doc/08 §1, §2, §3; doc/13 S9; P10).
//
// Pergunta: a Camada A escrita como gerador `sync*` com um `yield` por
// checkpoint, fatiada em orçamento de 4 ms no isolate principal, é viável no
// web para uma seção grande, e quanto perde em relação ao isolate nativo?
// Resultado em spike/RESULTADO-S9.md.
//
// Rodar nos três alvos (um arquivo por invocação):
//   flutter test test/spike/s9_cooperative_worker_test.dart
//   flutter test --platform chrome test/spike/s9_cooperative_worker_test.dart
//   flutter test --platform chrome --wasm test/spike/s9_cooperative_worker_test.dart
//
// `dart:isolate` é importado direto: com Dart 3.13.4 ele **compila** em dart2js
// e dart2wasm, e só falha em runtime (`UnsupportedError`). O teste de isolate
// é pulado com `skip: kIsWeb`, então não há chamada a `Isolate.run` no web.

import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/s9_cooperative_worker.dart';
import 'support/s9_sample_xhtml.dart';

const String _platform = kIsWasm
    ? 'chrome-wasm'
    : kIsWeb
    ? 'chrome-js'
    : 'vm';

void _log(String msg) => print('[S9 $_platform] $msg');

String _ms(num micros) => (micros / 1000).toStringAsFixed(2);

int _median(List<int> xs) => (List.of(xs)..sort())[xs.length ~/ 2];

/// Parse + caminhada, drenados de uma vez.
List<Block> _runDirect(String xhtml) {
  final out = BlockCollector();
  drain(parseSectionSteps(xhtml, out).iterator);
  return out.blocks;
}

Future<(List<Block>, CooperativeReport)> _runSliced(String xhtml) async {
  final out = BlockCollector();
  final report = await CooperativeRunner().run(
    parseSectionSteps(xhtml, out).iterator,
  );
  return (out.blocks, report);
}

int _timeMicros(void Function() f) {
  final sw = Stopwatch()..start();
  f();
  return sw.elapsedMicroseconds;
}

Future<int> _timeMicrosAsync(Future<void> Function() f) async {
  final sw = Stopwatch()..start();
  await f();
  return sw.elapsedMicroseconds;
}

void main() {
  late final String xhtml500k;
  late final String xhtml3m;
  late final String xhtmlPre;
  late final String xhtmlBigP;
  final directMedian = <String, int>{};
  final slicedMedian = <String, int>{};

  setUpAll(() {
    xhtml500k = sampleSectionXhtml(targetBytes: 500000);
    xhtml3m = sampleSectionXhtml(targetBytes: 3000000);
    xhtmlPre = sampleGiantBlockXhtml();
    xhtmlBigP = sampleGiantBlockXhtml(tag: 'p');
    // Aquecimento (JIT na VM; na web, a primeira execução também é mais lenta).
    _runDirect(xhtml500k);
    _log('Stopwatch.frequency = ${Stopwatch().frequency} Hz');
  });

  group('amostras', () {
    test('tamanhos e forma', () {
      final b = _runDirect(xhtml500k);
      _log(
        '500 KB: ${xhtml500k.length} unidades UTF-16, ${b.length} blocos, '
        '${b.where((x) => x.tag == 'p').length} <p>',
      );
      final b3 = _runDirect(xhtml3m);
      _log('3 MB: ${xhtml3m.length} unidades UTF-16, ${b3.length} blocos');
      _log('pre gigante: ${xhtmlPre.length} unidades UTF-16');
      expect(xhtml500k.length, inInclusiveRange(490000, 510000));
      expect(xhtml3m.length, inInclusiveRange(2990000, 3010000));
      expect(b.where((x) => x.tag == 'p').length, greaterThan(3500));
      for (final tag in ['h2', 'li', 'td', 'p']) {
        expect(b.any((x) => x.tag == tag), isTrue, reason: tag);
      }
      // blockquote > p vira blocos `p`, nunca um bloco `blockquote` duplicado.
      expect(b.any((x) => x.tag == 'blockquote'), isFalse);
      // Colapso de whitespace fora de `pre`.
      expect(b.every((x) => !x.text.contains('\n')), isTrue);
      expect(b.every((x) => !x.text.contains('  ')), isTrue);
    });
  });

  group('1. corretude: direto == fatiado', () {
    for (final (name, get) in [
      ('500 KB', () => xhtml500k),
      ('pre gigante', () => xhtmlPre),
      ('p gigante', () => xhtmlBigP),
    ]) {
      test(name, () async {
        final direct = _runDirect(get());
        final (sliced, report) = await _runSliced(get());
        expect(sliced.length, direct.length);
        expect(sliced, orderedEquals(direct));
        final chars = direct.fold(0, (s, b) => s + b.text.length);
        expect(sliced.fold(0, (s, b) => s + b.text.length), chars);
        // Um passo por bloco, mais o passo do parse.
        expect(report.steps, direct.length + 1);
        _log(
          'corretude $name: ${direct.length} blocos, $chars chars, '
          '${report.slices.length} fatias',
        );
      });
    }

    test('pre preserva whitespace', () {
      final pre = _runDirect(xhtmlPre).singleWhere((b) => b.tag == 'pre');
      expect(pre.text.length, greaterThanOrEqualTo(1000000));
      expect(pre.text, contains('\n'));
      expect(pre.text, contains('    '));
    });
  });

  group('2. parse atômico do html (mediana de 3)', () {
    for (final (name, get) in [
      ('500 KB', () => xhtml500k),
      ('3 MB', () => xhtml3m),
      ('pre 1 MB', () => xhtmlPre),
    ]) {
      test(name, () {
        final times = [
          for (var i = 0; i < 3; i++) _timeMicros(() => parseXhtml(get())),
        ];
        final walk = <int>[];
        for (var i = 0; i < 3; i++) {
          final doc = parseXhtml(get());
          walk.add(
            _timeMicros(
              () => drain(walkBlocksSteps(doc, BlockCollector()).iterator),
            ),
          );
        }
        _log(
          'parse $name: mediana ${_ms(_median(times))} ms '
          '(${times.map(_ms).join(' / ')}); caminhada sozinha: '
          'mediana ${_ms(_median(walk))} ms',
        );
        expect(_median(times), greaterThan(0));
      });
    }
  });

  group('3–4. fatiado a 4 ms vs direto', () {
    for (final (name, get) in [
      ('500 KB', () => xhtml500k),
      ('3 MB', () => xhtml3m),
    ]) {
      test(name, () async {
        final directTimes = [
          for (var i = 0; i < 3; i++) _timeMicros(() => _runDirect(get())),
        ];
        final reports = <CooperativeReport>[];
        for (var i = 0; i < 3; i++) {
          reports.add((await _runSliced(get())).$2);
        }
        final direct = _median(directTimes);
        final walls = reports.map((r) => r.wallMicros).toList();
        final wall = _median(walls);
        final r = reports.firstWhere((x) => x.wallMicros == wall);
        final walk = r.walkSlices.map((s) => s.micros).toList();
        final allWalk = [
          for (final x in reports) ...x.walkSlices.map((s) => s.micros),
        ];
        final parseSlice = r.sliceOfStep(0);
        final gaps = r.gapMicros;
        final over4 = allWalk.where((m) => m > 4000).length;
        final over8 = allWalk.where((m) => m > 8000).length;
        final maxWalk = allWalk.reduce((a, b) => a > b ? a : b);
        final meanWalk = walk.reduce((a, b) => a + b) / walk.length;
        final medianWalk = _median(allWalk);
        final meanGap = gaps.isEmpty
            ? 0
            : gaps.reduce((a, b) => a + b) / gaps.length;
        final maxGap = gaps.isEmpty ? 0 : gaps.reduce((a, b) => a > b ? a : b);
        directMedian[name] = direct;
        slicedMedian[name] = wall;
        _log(
          'fatiado $name: ${r.slices.length} fatias; fatia do parse '
          '${_ms(parseSlice.micros)} ms (${parseSlice.steps} passos); '
          'caminhada: média ${_ms(meanWalk)} ms; nas 3 execuções: mediana '
          '${_ms(medianWalk)} ms, máx ${_ms(maxWalk)} ms, '
          '>4 ms: $over4/${allWalk.length}, '
          '>8 ms: $over8/${allWalk.length}; ocupado ${_ms(r.busyMicros)} ms; '
          'cessão: média ${_ms(meanGap)} ms, máx ${_ms(maxGap)} ms; '
          'parede mediana ${_ms(wall)} ms (${walls.map(_ms).join(' / ')}); '
          'parede sem a fatia do parse ${_ms(wall - parseSlice.micros)} ms',
        );
        _log(
          'direto $name: mediana ${_ms(direct)} ms '
          '(${directTimes.map(_ms).join(' / ')}); '
          'razão fatiado/direto = ${(wall / direct).toStringAsFixed(2)}',
        );
        // O passo indivisível é um bloco de prosa (< 1 KB): a fatia típica
        // da caminhada fica no orçamento. Média e máximo são registrados, não
        // afirmados: com 3 a 10 fatias por execução, uma pausa de GC de 10 ms
        // move a média, e o agendador do navegador entra no máximo.
        expect(medianWalk, lessThanOrEqualTo(5000));
        expect(r.steps, greaterThan(3000));
      });
    }
  });

  group('5. Isolate.run (só VM)', () {
    for (final (name, get) in [
      ('500 KB', () => xhtml500k),
      ('3 MB', () => xhtml3m),
    ]) {
      test(name, skip: kIsWeb ? 'sem isolates no web' : null, () async {
        final src = get();
        final times = <int>[];
        var blocks = 0;
        for (var i = 0; i < 3; i++) {
          times.add(
            await _timeMicrosAsync(() async {
              final result = await Isolate.run(() => _runDirect(src));
              blocks = result.length;
            }),
          );
        }
        final spawn = [
          for (var i = 0; i < 3; i++)
            await _timeMicrosAsync(() => Isolate.run(() => 0)),
        ];
        final iso = _median(times);
        final coop = slicedMedian[name];
        final direct = directMedian[name];
        _log(
          'isolate $name: mediana ${_ms(iso)} ms '
          '(${times.map(_ms).join(' / ')}), $blocks blocos devolvidos; '
          'Isolate.run vazio: mediana ${_ms(_median(spawn))} ms; '
          'cooperativo/isolate = '
          '${coop == null ? '?' : (coop / iso).toStringAsFixed(2)}; '
          'isolate/direto = '
          '${direct == null ? '?' : (iso / direct).toStringAsFixed(2)}',
        );
        expect(blocks, greaterThan(3000));
      });
    }
  });

  group('6. bloco gigante', () {
    for (final (name, tag, get) in [
      ('pre de 1 MB', 'pre', () => xhtmlPre),
      ('p de 1 MB (regex de whitespace)', 'p', () => xhtmlBigP),
    ]) {
      test('$name: fatia que o contém', () async {
        final direct = _runDirect(get());
        final idx = direct.indexWhere((b) => b.text.length > 500000);
        expect(direct[idx].tag, tag);
        final step = idx + 1; // passo 0 é o parse
        final reports = <CooperativeReport>[];
        for (var i = 0; i < 3; i++) {
          reports.add((await _runSliced(get())).$2);
        }
        final giant = reports.map((r) => r.sliceOfStep(step)).toList();
        final parse = reports.map((r) => r.sliceOfStep(0)).toList();
        // Custo do passo sozinho: drena com Stopwatch por passo.
        final stepOnly = <int>[];
        for (var i = 0; i < 3; i++) {
          final t = drainTimed(
            parseSectionSteps(get(), BlockCollector()).iterator,
          );
          stepOnly.add(t[step]);
        }
        _log(
          'gigante $name: fatia que o contém '
          '${giant.map((s) => '${_ms(s.micros)} ms/${s.steps} passos').join(' / ')}; '
          'só o passo: mediana ${_ms(_median(stepOnly))} ms '
          '(${stepOnly.map(_ms).join(' / ')}); fatia do parse '
          '${parse.map((s) => _ms(s.micros)).join(' / ')} ms',
        );
        expect(giant.every((s) => s.containsStep(step)), isTrue);
      });
    }
  });
}
