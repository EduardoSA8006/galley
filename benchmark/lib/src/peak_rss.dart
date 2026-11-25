import 'dart:io';

final RegExp _vmHwm = RegExp(r'^VmHWM:\s+(\d+)\s+kB', multiLine: true);

/// Pico de memória residente do processo atual, em bytes.
///
/// No Linux lê `VmHWM` de `/proc/self/status`, que é do próprio processo.
/// `ProcessInfo.maxRss` (`ru_maxrss`) herda o pico do processo pai no `fork`
/// e o mantém após o `exec`, então um filho lançado por um pai grande
/// reportaria o pico do pai. Fora do Linux (sem `/proc`), cai em
/// `ProcessInfo.maxRss`, sujeito a esse viés.
int peakRssBytes() {
  try {
    final m = _vmHwm.firstMatch(File('/proc/self/status').readAsStringSync());
    if (m != null) return int.parse(m[1]!) * 1024;
  } on FileSystemException {
    // Sem /proc: usa o valor do sistema.
  }
  return ProcessInfo.maxRss;
}
