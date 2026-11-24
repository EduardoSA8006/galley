import 'package:xml/xml.dart';

/// Namespace Dublin Core.
const String dcNamespace = 'http://purl.org/dc/elements/1.1/';

/// Namespace do OPF.
const String opfNamespace = 'http://www.idpf.org/2007/opf';

/// Elemento do OPF: namespace OPF ou, por leniência, sem namespace.
bool isOpfElement(XmlElement e, String local) {
  if (e.name.local != local) return false;
  final ns = e.name.namespaceUri;
  return ns == null || ns.isEmpty || ns == opfNamespace;
}

/// Elemento Dublin Core de nome local [local], com qualquer prefixo.
bool isDcElement(XmlElement e, String local) =>
    e.name.local == local && e.name.namespaceUri == dcNamespace;

/// Atributo de nome local [local], com namespace OPF ou sem prefixo.
String? opfAttribute(XmlElement e, String local) {
  for (final a in e.attributes) {
    if (a.name.local != local) continue;
    final ns = a.name.namespaceUri;
    if (ns == null || ns.isEmpty || ns == opfNamespace) return a.value;
  }
  return null;
}

/// Divide um atributo `properties` em tokens (qualquer espaço em branco).
Set<String> splitProperties(String? value) => {
  for (final t in (value ?? '').split(RegExp(r'\s+')))
    if (t.isNotEmpty) t,
};
