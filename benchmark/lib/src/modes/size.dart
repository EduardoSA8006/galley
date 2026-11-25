import 'dart:convert';
import 'dart:io';

import '../bmf.dart' as bmf;
import 'build.dart';
import 'orchestration.dart';

/// Teto de bytes adicionados ao app: 2 MiB.
const int sizeBudgetBytes = 2097152;

/// Chave do benchmark no BMF.
const String sizeBenchmarkKey = 'size/galley-delta-arm64';

/// Caminho (relativo ao app) do APK arm64 de release gerado por
/// `flutter build apk --split-per-abi`.
const String arm64ApkPath =
    'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk';

/// Bytes que o `galley` acrescenta: tamanho de [withApk] menos o de
/// [withoutApk].
int sizeDelta(File withApk, File withoutApk) =>
    withApk.lengthSync() - withoutApk.lengthSync();

/// Se [delta] cabe no [budget] (padrão 2 MiB, inclusive).
bool sizeWithinBudget(int delta, {int budget = sizeBudgetBytes}) =>
    delta <= budget;

/// BMF com o [delta] em `size-bytes`.
Map<String, Object> sizeBmf(int delta) => bmf.toBmf({
  sizeBenchmarkKey: [
    bmf.Measure(slug: bmf.MeasureSlug.sizeBytes, value: delta.toDouble()),
  ],
});

Future<File> _build(Directory app, StringSink log) async {
  log.writeln(
    'Compilando ${app.uri.pathSegments.where((s) => s.isNotEmpty).last}…',
  );
  final get = await Process.run('flutter', [
    'pub',
    'get',
  ], workingDirectory: app.path);
  if (get.exitCode != 0) {
    throw MeasurementFailure('flutter pub get falhou:\n${get.stderr}');
  }
  final build = await Process.run('flutter', [
    'build',
    'apk',
    '--release',
    '--split-per-abi',
    '--target-platform',
    'android-arm64',
  ], workingDirectory: app.path);
  if (build.exitCode != 0) {
    throw MeasurementFailure(
      'flutter build apk falhou em ${app.path}:\n${build.stdout}\n${build.stderr}',
    );
  }
  final apk = File('${app.path}/$arm64ApkPath');
  if (!apk.existsSync()) {
    throw MeasurementFailure('APK não encontrado: ${apk.path}');
  }
  return apk;
}

/// Executa o modo `size`: compila os dois apps de `benchmark/size/` (release,
/// split por ABI, arm64), calcula a diferença de bytes e confere o teto.
///
/// Escreve o BMF em [outPath] (se dado). Devolve 0 dentro do teto, 1 acima
/// dele e [exitMeasurementFailure] se a compilação falhou.
Future<int> runSize({String? outPath, StringSink? log}) async {
  final logSink = log ?? stderr;
  try {
    final root = await repoRoot();
    final withApk = await _build(
      Directory('${root.path}/benchmark/size/with_galley'),
      logSink,
    );
    final withoutApk = await _build(
      Directory('${root.path}/benchmark/size/without_galley'),
      logSink,
    );
    final delta = sizeDelta(withApk, withoutApk);
    if (outPath != null) {
      await File(outPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(sizeBmf(delta)),
      );
    }
    final ok = sizeWithinBudget(delta);
    stdout.writeln(
      'Delta do APK arm64: $delta bytes '
      '(${(delta / 1048576).toStringAsFixed(3)} MiB; teto $sizeBudgetBytes). '
      '${ok ? 'dentro do teto' : 'ACIMA do teto'}',
    );
    return ok ? 0 : 1;
  } on MeasurementFailure catch (e) {
    logSink.writeln(e.message);
    return exitMeasurementFailure;
  }
}
