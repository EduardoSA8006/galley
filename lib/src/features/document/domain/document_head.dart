import 'package:meta/meta.dart';

/// Folha de estilo de um documento, na ordem em que aparece.
@immutable
sealed class StyleSheetRef {
  const StyleSheetRef({this.media});

  /// Valor do atributo `media`, se houver.
  final String? media;
}

/// Folha de estilo externa referenciada por `<link rel="stylesheet">`.
final class LinkedStyleSheet extends StyleSheetRef {
  /// Cria a referência; [path] é o caminho da folha no zip.
  const LinkedStyleSheet({required this.path, super.media, this.title});

  /// Caminho da folha no zip (sem `/` inicial).
  final String path;

  /// Valor do atributo `title`, se houver.
  final String? title;
}

/// Folha de estilo embutida em um `<style>`.
final class InlineStyleSheet extends StyleSheetRef {
  /// Cria a folha; [css] é o texto bruto do elemento.
  const InlineStyleSheet({required this.css, super.media});

  /// Texto bruto do `<style>`.
  final String css;
}

/// Dados extraídos do `<head>` de um documento (folhas de estilo, título,
/// `lang`/`dir`, viewport).
@immutable
final class DocumentHead {
  /// Cria o head com os dados extraídos.
  const DocumentHead({
    this.styleSheets = const [],
    this.title,
    this.lang,
    this.dir,
    this.viewport,
  });

  /// Folhas de estilo, na ordem do documento.
  final List<StyleSheetRef> styleSheets;

  /// Texto de `<title>`, aparado e com espaços colapsados.
  final String? title;

  /// Idioma: `<html lang>` ou, na falta, `xml:lang`.
  final String? lang;

  /// Valor de `<html dir>`.
  final String? dir;

  /// `content` de `<meta name="viewport">`.
  final String? viewport;

  /// Head sem nenhum dado.
  static const DocumentHead empty = DocumentHead();
}
