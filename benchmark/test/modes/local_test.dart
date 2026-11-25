import 'dart:convert';
import 'dart:io';

import 'package:galley_benchmark/src/corpus/private_corpus.dart';
import 'package:galley_benchmark/src/corpus/synthetic.dart';
import 'package:galley_benchmark/src/modes/build.dart';
import 'package:galley_benchmark/src/modes/local.dart';
import 'package:galley_benchmark/src/modes/stats.dart';
import 'package:test/test.dart';

void main() {
  group('anonymousId', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('galley-anon-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'são 12 hex do sha256 do conteúdo, estáveis e sem depender do nome',
      () {
        final a = File('${dir.path}/Livro Secreto.epub')
          ..writeAsBytesSync([1, 2, 3]);
        final b = File('${dir.path}/outro-nome.epub')
          ..writeAsBytesSync([1, 2, 3]);
        final c = File('${dir.path}/c.epub')..writeAsBytesSync([1, 2, 4]);
        // sha256 de 0x010203.
        expect(anonymousId(a), '039058c6f2c0');
        expect(anonymousId(a), anonymousId(a));
        expect(anonymousId(b), anonymousId(a));
        expect(anonymousId(c), isNot(anonymousId(a)));
        expect(anonymousId(a), matches(RegExp(r'^[0-9a-f]{12}$')));
      },
    );
  });

  group('listPrivateCorpus', () {
    test('variável ausente: lista vazia e aviso', () async {
      final warnings = <String>[];
      final files = await listPrivateCorpus(
        environment: const {},
        onWarning: warnings.add,
      );
      expect(files, isEmpty);
      expect(warnings.single, contains('GALLEY_PRIVATE_CORPUS'));
    });

    test('diretório inexistente: lista vazia e aviso sem o caminho', () async {
      final warnings = <String>[];
      final files = await listPrivateCorpus(
        environment: const {'GALLEY_PRIVATE_CORPUS': '/nao/existe/segredo'},
        onWarning: warnings.add,
      );
      expect(files, isEmpty);
      expect(warnings.single, isNot(contains('segredo')));
    });

    test('lista só .epub, recursivamente', () async {
      final dir = Directory.systemTemp.createTempSync('galley-priv-');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/a.epub').writeAsBytesSync([1]);
      File('${dir.path}/notas.txt').writeAsStringSync('x');
      Directory('${dir.path}/sub').createSync();
      File('${dir.path}/sub/b.EPUB').writeAsBytesSync([2]);
      final files = await listPrivateCorpus(
        environment: {'GALLEY_PRIVATE_CORPUS': dir.path},
        onWarning: (_) {},
      );
      expect(files.map((f) => f.uri.pathSegments.last).toSet(), {
        'a.epub',
        'b.EPUB',
      });
    });
  });

  group('privateScrubber', () {
    test('troca nome, nome sem extensão, caminho e diretório', () {
      final f = File('/tmp/Pasta Reservada/Livro Secreto.epub');
      final scrub = privateScrubber([f], root: '/tmp/Pasta Reservada');
      final text =
          'erro em ${f.path} (Livro Secreto.epub, Livro Secreto) '
          'file:///tmp/Pasta%20Reservada/Livro%20Secreto.epub';
      final out = scrub(text);
      for (final leak in ['Livro', 'Secreto', 'Reservada']) {
        expect(out, isNot(contains(leak)));
      }
      expect(out, contains('<privado>'));
    });
  });

  group('percentile', () {
    test('p95 por posto mais próximo', () {
      final xs = [for (var i = 1; i <= 20; i++) i.toDouble()];
      expect(percentile(xs, 0.95), 19);
      expect(percentile([5], 0.95), 5);
      expect(percentile([3, 1, 2], 1), 3);
    });
  });

  group('readLocalGitState', () {
    late Directory repo;

    Future<void> git(List<String> args) async {
      final r = await Process.run('git', args, workingDirectory: repo.path);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    }

    setUp(() async {
      repo = Directory.systemTemp.createTempSync('galley-gitstate-');
      await git(['init', '-q', '-b', 'feat/x']);
      await git(['config', 'user.email', 't@example.com']);
      await git(['config', 'user.name', 't']);
      await git(['config', 'commit.gpgsign', 'false']);
      File('${repo.path}/a.txt').writeAsStringSync('1');
      await git(['add', '.']);
      await git(['commit', '-q', '-m', 'c']);
    });
    tearDown(() => repo.deleteSync(recursive: true));

    test('árvore limpa: sha do HEAD, branch atual e dirty falso', () async {
      final s = await readLocalGitState(repo);
      expect(s.sha, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(s.branch, 'feat/x');
      expect(s.dirty, isFalse);
    });

    test('arquivo modificado ou novo deixa a árvore suja', () async {
      File('${repo.path}/a.txt').writeAsStringSync('2');
      expect((await readLocalGitState(repo)).dirty, isTrue);
      await git(['checkout', '-q', '--', 'a.txt']);
      File('${repo.path}/novo.txt').writeAsStringSync('n');
      expect((await readLocalGitState(repo)).dirty, isTrue);
    });

    test('HEAD destacado: branch HEAD', () async {
      await git(['checkout', '-q', '--detach']);
      expect((await readLocalGitState(repo)).branch, 'HEAD');
    });
  });

  group('parseMeasureOpen', () {
    test('lê ns, rss e checksum', () {
      final m = parseMeasureOpen('ns=10\nrss=2048\nchecksum=-7\n');
      expect((m.ns, m.rss, m.checksum), (10, 2048, -7));
    });
    test('saída incompleta lança FormatException', () {
      expect(
        () => parseMeasureOpen('ns=1\nchecksum=2\n'),
        throwsFormatException,
      );
    });
  });

  group('runLocal', () {
    late Directory work;
    late File exe;

    setUpAll(() async {
      work = Directory.systemTemp.createTempSync('galley-local-test-');
      exe = await compileRunner(
        checkout: Directory('..'),
        outPath: '${work.path}/runner',
      );
    });
    tearDownAll(() => work.deleteSync(recursive: true));

    Future<({int code, String bmf, String report, String log})> run(
      Map<String, String> env,
    ) async {
      final out = '${work.path}/bmf.json';
      final rep = '${work.path}/report.md';
      final log = StringBuffer();
      final code = await runLocal(
        outPath: out,
        reportPath: rep,
        runs: 3,
        syntheticSizes: const [],
        includePublic: false,
        runnerExe: exe,
        environment: env,
        log: log,
        echoReport: false,
      );
      return (
        code: code,
        bmf: File(out).readAsStringSync(),
        report: File(rep).readAsStringSync(),
        log: log.toString(),
      );
    }

    test(
      'corpus privado é anonimizado no BMF, no relatório e no log',
      () async {
        final priv = Directory('${work.path}/Pasta Reservada')..createSync();
        final a = await writeSyntheticBook(
          '${priv.path}/Livro Secreto.epub',
          targetBytes: 300 * 1024,
          chapters: 4,
        );
        final b = await writeSyntheticBook(
          '${priv.path}/Livro Secreto 2.epub',
          targetBytes: 400 * 1024,
          chapters: 5,
        );
        // Um terceiro, corrompido: a falha não pode vazar o nome nem o caminho.
        File('${priv.path}/Quebrado Secreto.epub')
            .writeAsStringSync('nao é zip');
        final r = await run({'GALLEY_PRIVATE_CORPUS': priv.path});
        // Falha de um livro: código 70, mas BMF e relatório saem assim mesmo.
        expect(r.code, 70, reason: r.log);

        final all = '${r.bmf}\n${r.report}\n${r.log}';
        for (final leak in [
          'Livro Secreto',
          'Quebrado Secreto',
          'Pasta Reservada',
          priv.path,
          work.path,
        ]) {
          expect(all, isNot(contains(leak)), reason: 'vazou: $leak');
        }
        final bmf = jsonDecode(r.bmf) as Map<String, Object?>;
        for (final f in [a, b]) {
          final key = 'private/${anonymousId(f)}';
          expect(bmf, contains(key));
          final m = bmf[key]! as Map<String, Object?>;
          expect(m.keys, containsAll(['wall-time-ns', 'peak-rss-bytes']));
          expect(r.report, contains(key));
        }
        final agg = bmf['private/aggregate']! as Map<String, Object?>;
        final wall = agg['wall-time-ns']! as Map<String, Object?>;
        expect(wall, contains('value'));
        expect(wall, contains('upper_value'));
        expect(agg, contains('peak-rss-bytes'));
        // O livro corrompido aparece só com id anônimo.
        expect(r.log, contains('private/'));
      },
    );

    test('sem a variável: sem erro e com aviso no relatório', () async {
      final r = await run(const {});
      expect(r.code, 0, reason: r.log);
      expect(r.report, contains('GALLEY_PRIVATE_CORPUS'));
      expect(jsonDecode(r.bmf) as Map, isNot(contains('private/aggregate')));
    });

    test('--upload sem token pula com aviso e sai com 0', () async {
      final log = StringBuffer();
      final code = await runLocal(
        outPath: '${work.path}/up.json',
        runs: 1,
        syntheticSizes: const [],
        includePublic: false,
        runnerExe: exe,
        environment: const {},
        upload: true,
        gitState: (_) async => _clean,
        log: log,
        echoReport: false,
      );
      expect(code, 0, reason: '$log');
      expect('$log', contains('BENCHER_API_KEY'));
    });

    Future<({int code, String log, List<String>? command})> upload(
      LocalGitState state, {
      bool allowDirty = false,
    }) async {
      final out = File('${work.path}/upload.json');
      if (out.existsSync()) out.deleteSync();
      final log = StringBuffer();
      List<String>? command;
      final code = await runLocal(
        outPath: out.path,
        runs: 1,
        syntheticSizes: const [],
        includePublic: false,
        runnerExe: exe,
        environment: const {'BENCHER_API_KEY': 'k'},
        upload: true,
        allowDirty: allowDirty,
        gitState: (_) async => state,
        bencherRunner: (cmd, env) async {
          command = cmd;
          return 0;
        },
        log: log,
        echoReport: false,
      );
      // O BMF sai sempre, com ou sem envio.
      expect(out.existsSync(), isTrue);
      return (code: code, log: '$log', command: command);
    }

    test('--upload envia o commit medido e o branch atual', () async {
      final r = await upload(
        LocalGitState(sha: 'b' * 40, branch: r'feat/a b$', dirty: false),
      );
      expect(r.code, 0, reason: r.log);
      final cmd = r.command!;
      String arg(String flag) => cmd[cmd.indexOf(flag) + 1];
      expect(arg('--testbed'), 'local-dev');
      expect(arg('--hash'), 'b' * 40);
      expect(arg('--branch'), 'feat/a-b-');
    });

    test('--upload com árvore suja recusa o envio, com aviso', () async {
      final r = await upload(
        LocalGitState(sha: 'c' * 40, branch: 'main', dirty: true),
      );
      expect(r.code, 0, reason: r.log);
      expect(r.command, isNull);
      expect(r.log, contains('--allow-dirty'));
    });

    test('--upload com árvore suja e --allow-dirty envia', () async {
      final r = await upload(
        LocalGitState(sha: 'c' * 40, branch: 'main', dirty: true),
        allowDirty: true,
      );
      expect(r.code, 0, reason: r.log);
      expect(r.command, contains('c' * 40));
    });
  });
}

const LocalGitState _clean = LocalGitState(
  sha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  branch: 'main',
  dirty: false,
);
