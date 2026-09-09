import '../corpus_case.dart';
import 'common.dart';

const _group = 'escrita';

List<CorpusCase> escritaCases() => [
      CorpusCase(
        group: _group,
        slug: 'arabe-rtl',
        readme: 'Árabe com `dir="rtl"`, `page-progression-direction="rtl"` e números em algarismos ocidentais no meio: bidi, ordem de páginas e virada invertida.',
        build: () {
          const body = '<h1>الباب المفتوح</h1><p>كان الباب مفتوحاً منذ البداية، ولم يلاحظ أحد ذلك. كان النهر ينزل ببطء بين الحجارة حاملاً الأوراق والذكريات.</p>'
              '<p>في عام 1998 كتبت الرسالة ووضعتها في الدرج، ثم تظاهرت بأن اليوم عادي.</p>'
              '<p>هناك صمت قديم في ذلك البيت، من النوع الذي يُورَث.</p>';
          final b = singleChapterBook('arabe-rtl', body, title: 'الباب المفتوح', lang: 'ar', dir: 'rtl');
          b.direction = 'rtl';
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'hebraico-rtl',
        readme: 'Hebraico com `dir="rtl"` e `page-progression-direction="rtl"`, com uma palavra latina embutida.',
        build: () {
          const body = '<h1>הדלת הפתוחה</h1><p>הדלת הייתה פתוחה מההתחלה, ואף אחד לא שם לב. הנהר ירד באיטיות בין האבנים, נושא עלים וזיכרונות.</p>'
              '<p>היא שמרה את המכתב במגירה — כתוב באנגלית, <span lang="en" dir="ltr">Dear friend</span> — והתנהגה כאילו היום רגיל.</p>';
          final b = singleChapterBook('hebraico-rtl', body, title: 'הדלת הפתוחה', lang: 'he', dir: 'rtl');
          b.direction = 'rtl';
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'japones-lang',
        readme: 'Japonês com `xml:lang="ja"` usando os kanji 直, 骨 e 海 (formas diferentes em zh): unificação Han resolvida por `locale`.',
        build: () {
          const body = '<h1>海の匂い</h1><p>直接、骨の髄まで海の匂いがした。扉は最初から開いていたのに、誰も気づかなかった。</p>'
              '<p>時計がいつ止まったのか、誰にも言えなかった。</p>';
          return singleChapterBook('japones-lang', body, title: '海の匂い', lang: 'ja').build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'chines-lang',
        readme: 'Chinês simplificado com `xml:lang="zh-Hans"` usando os mesmos kanji 直, 骨 e 海 do caso japonês: os glifos devem sair diferentes.',
        build: () {
          const body = '<h1>海的味道</h1><p>直接闻到骨子里的海的味道。门从一开始就是开着的，可谁也没注意到。</p>'
              '<p>谁也说不清客厅的钟是什么时候停的。</p>';
          return singleChapterBook('chines-lang', body, title: '海的味道', lang: 'zh-Hans').build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'grego-politonico',
        readme: 'Grego politônico (diacríticos combinados e pré-compostos): normalização NFC e fallback de fonte.',
        build: () {
          const body = '<h1>Ἐν ἀρχῇ</h1><p>Ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν, καὶ θεὸς ἦν ὁ λόγος.</p>'
              '<p>Forma decomposta do mesmo trecho: Ἐν ἀρχῇ ἦν ὁ λόγος.</p>';
          return singleChapterBook('grego-politonico', body, title: 'Ἐν ἀρχῇ', lang: 'grc').build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'devanagari',
        readme: 'Hindi em devanágari (conjuntos e matras): shaping complexo e limites de palavra.',
        build: () {
          const body = '<h1>खुला दरवाज़ा</h1><p>दरवाज़ा शुरू से ही खुला था, और किसी ने ध्यान नहीं दिया। नदी पत्थरों के बीच धीरे-धीरे बह रही थी।</p>'
              '<p>उसने चिट्ठी दराज़ में रख दी और ऐसा दिखाया जैसे दिन सामान्य हो।</p>';
          return singleChapterBook('devanagari', body, title: 'खुला दरवाज़ा', lang: 'hi').build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'bidi-misto',
        readme: 'Hebraico e árabe dentro de parágrafos em português (livro ltr): bidi intra-parágrafo sem afetar a direção do bloco.',
        build: () {
          const body = '<h1>Mistura</h1><p>Ela disse apenas <span lang="he">שלום עולם</span> e saiu pela porta.</p>'
              '<p>O cartaz trazia <span lang="ar">مرحبا بالعالم</span> em letras grandes, seguido de 2026 em algarismos.</p>'
              '<p dir="rtl" lang="he">פסקה שלמה בעברית בתוך ספר בפורטוגזית.</p>';
          return singleChapterBook('bidi-misto', body, title: 'Mistura').build();
        },
      ),
    ];
