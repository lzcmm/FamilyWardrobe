/**
 * 核心逻辑验证测试
 *
 * 用 Node 直接跑，验证推荐引擎、Lab 取色、层级顺序的真实行为。
 * 目的是在没有 Xcode 的环境下，证明算法逻辑是对的。
 */

const L = require('./logic');

let passed = 0;
let failed = 0;
const failures = [];

function check(name, condition, detail) {
  if (condition) {
    passed++;
    console.log(`  ✓ ${name}`);
  } else {
    failed++;
    failures.push(`${name}${detail ? ' — ' + detail : ''}`);
    console.log(`  ✗ ${name}${detail ? ' — ' + detail : ''}`);
  }
}

function section(title) {
  console.log(`\n${title}`);
}

// ─────────────────────────────────────────────
// 测试数据
// ─────────────────────────────────────────────

const COLORS = ['#1C1C1E', '#F5F5F0', '#4C63E6', '#8B6A4E', '#C9A87C', '#4A8C5A'];
const LAYERS = [
  L.WearLayer.top, L.WearLayer.top, L.WearLayer.top,
  L.WearLayer.bottom, L.WearLayer.bottom, L.WearLayer.bottom,
  L.WearLayer.shoes, L.WearLayer.shoes,
  L.WearLayer.outerwear, L.WearLayer.dress,
  L.WearLayer.acc, L.WearLayer.bag,
];

let idCounter = 0;
function makeGarments(profileID, count = 12, opts = {}) {
  const { seasons = ['春', '秋'], occasions = ['通勤'], fits = null } = opts;
  return Array.from({ length: count }, (_, i) => ({
    id: `g${++idCounter}`,
    profileID,
    layer: LAYERS[i % LAYERS.length],
    colorName: `色${i % COLORS.length}`,
    colorHex: COLORS[i % COLORS.length],
    material: ['cotton', 'knit', 'silk', 'denim'][i % 4],
    fit: fits ? fits[i % fits.length] : 'regular',
    occasions: [...occasions],
    seasons: [...seasons],
    wearCount: i % 5,
    lastWornDate: null,
    archived: false,
  }));
}

// ─────────────────────────────────────────────

section('1. 穿戴层级顺序');
{
  check('头饰在最上', L.LAYER_ORDER[0] === L.WearLayer.headwear);
  check('包袋在最下', L.LAYER_ORDER[L.LAYER_ORDER.length - 1] === L.WearLayer.bag);
  check(
    '上衣 < 连衣裙 < 外套 < 下装',
    L.LAYER_ORDER.indexOf(L.WearLayer.top) < L.LAYER_ORDER.indexOf(L.WearLayer.dress) &&
    L.LAYER_ORDER.indexOf(L.WearLayer.dress) < L.LAYER_ORDER.indexOf(L.WearLayer.outerwear) &&
    L.LAYER_ORDER.indexOf(L.WearLayer.outerwear) < L.LAYER_ORDER.indexOf(L.WearLayer.bottom)
  );

  const order = L.overlayOrder();
  check('遮挡顺序覆盖全部 9 层', order.length === 9 && new Set(order).size === 9);
  check('遮挡顺序由枚举倒序派生', order[0] === L.WearLayer.bag && order[8] === L.WearLayer.headwear);

  check('连衣裙覆盖上衣+下装', L.coversLayers(L.WearLayer.dress).length === 2);
  check('上衣不覆盖任何层', L.coversLayers(L.WearLayer.top).length === 0);
}

section('2. 档案隔离（回归测试）');
{
  const myId = 'profile-mine';
  const otherId = 'profile-other';

  const mine = makeGarments(myId, 12);
  const theirs = makeGarments(otherId, 12, { seasons: ['夏'] });

  const pool = L.buildPool([...mine, ...theirs], myId, '通勤', '春');
  check('候选池不含他人档案的单品', pool.every((g) => g.profileID === myId),
    `混入 ${pool.filter((g) => g.profileID !== myId).length} 件`);
  check('候选池排除季节不符的单品', pool.every((g) => g.seasons.includes('春')));

  const results = L.recommend({
    garments: [...mine, ...theirs],
    occasion: '通勤', season: '春', profileID: myId,
  });
  check('推荐结果全属当前档案',
    results.every((r) => r.garments.every((g) => g.profileID === myId)));
}

section('3. 推荐引擎');
{
  const profileID = 'p1';
  const garments = makeGarments(profileID, 20);

  const results = L.recommend({
    garments, occasion: '通勤', season: '春', profileID,
  });

  check('能产出推荐', results.length > 0, `产出 ${results.length} 条`);
  check('每条都有理由', results.every((r) => r.reasons.length > 0));
  check('理由非空且可验证', results.every((r) =>
    r.reasons.every((t) => t.length >= 4 && !t.includes('很适合') && !t.includes('气质'))
  ));

  let descending = true;
  for (let i = 1; i < results.length; i++) {
    if (results[i - 1].score < results[i].score) descending = false;
  }
  check('分数递减', descending);

  const empty = L.recommend({ garments: [], occasion: '通勤', season: '春', profileID: 'x' });
  check('空衣橱不报错', Array.isArray(empty) && empty.length === 0);
}

section('4. 最近穿过的降权');
{
  const profileID = 'p2';
  const garments = makeGarments(profileID, 20);
  const recent = new Set(garments.filter((g) => g.layer === L.WearLayer.top).map((g) => g.id));

  const results = L.recommend({
    garments, occasion: '通勤', season: '春', profileID, recentIDs: recent,
  });

  const first = results[0];
  const topCount = first ? first.garments.filter((g) => g.layer === L.WearLayer.top).length : 0;
  check('第一套最多含 1 件最近穿过的上衣', topCount <= 1, `实际 ${topCount} 件`);

  const withFreshness = results.some((r) => r.reasons.some((t) => t.includes('最近穿过')));
  check('理由中体现「最近穿过」', withFreshness);
}

section('5. 协调随机（30 次）');
{
  const profileID = 'p3';
  const garments = makeGarments(profileID, 24);

  let allWearable = true;
  let emptyCount = 0;
  const signatures = new Set();

  for (let i = 0; i < 30; i++) {
    const results = L.inspire({
      garments, occasion: '通勤', season: '春', profileID, count: 1,
    });
    if (results.length === 0 || results[0].garments.length === 0) {
      emptyCount++;
      continue;
    }
    const layers = new Set(results[0].garments.map((g) => g.layer));
    const wearable = layers.has(L.WearLayer.top) || layers.has(L.WearLayer.dress);
    if (!wearable) allWearable = false;
    signatures.add(results[0].garments.map((g) => g.id).sort().join());
  }

  check('30 次随机都产出结果', emptyCount === 0, `空结果 ${emptyCount} 次`);
  check('30 次随机都「穿得出门」（含上衣或连衣裙）', allWearable);
  check('随机有变化（不是固定一套）', signatures.size >= 3, `仅 ${signatures.size} 种组合`);
}

section('6. 纯随机 vs 协调随机（对比验证）');
{
  const profileID = 'p4';
  const garments = makeGarments(profileID, 30);

  // 模拟纯随机：随机抽 3 件
  let pureRandomWearable = 0;
  for (let i = 0; i < 200; i++) {
    const picks = [];
    for (let j = 0; j < 3; j++) {
      picks.push(garments[Math.floor(Math.random() * garments.length)]);
    }
    const layers = new Set(picks.map((g) => g.layer));
    if (layers.has(L.WearLayer.top) || layers.has(L.WearLayer.dress)) pureRandomWearable++;
  }
  const pureRate = pureRandomWearable / 200;

  // 协调随机 200 次
  let coordWearable = 0;
  for (let i = 0; i < 200; i++) {
    const results = L.inspire({
      garments, occasion: '通勤', season: '春', profileID, count: 1,
    });
    if (results.length === 0) continue;
    const layers = new Set(results[0].garments.map((g) => g.layer));
    if (layers.has(L.WearLayer.top) || layers.has(L.WearLayer.dress)) coordWearable++;
  }
  const coordRate = coordWearable / 200;

  console.log(`    纯随机可用率: ${(pureRate * 100).toFixed(1)}%`);
  console.log(`    协调随机可用率: ${(coordRate * 100).toFixed(1)}%`);
  // 纯随机的基线取决于数据构成（测试数据里上衣/连衣裙占 1/3），
  // 所以只看「协调随机显著优于纯随机」这个相对关系
  check('协调随机可用率高于纯随机', coordRate > pureRate, `${(coordRate*100).toFixed(1)}% vs ${(pureRate*100).toFixed(1)}%`);
  check('协调随机可用率接近 100%', coordRate > 0.95, `实际 ${(coordRate * 100).toFixed(1)}%`);
}

section('7. 日历 Lab 取色归一化');
{
  const white = L.srgbToLab(255, 255, 255);
  check('白色 L > 95', white.L > 95, `L=${white.L.toFixed(1)}`);
  const whiteChroma = Math.sqrt(white.a * white.a + white.b * white.b);
  check('白色彩度 < 5', whiteChroma < 5, `彩度=${whiteChroma.toFixed(2)}`);

  const single = [{ colorHex: '#FF0000' }];
  check('单件衣服不算多彩', L.dayColorStep(single) === 0);

  const neutrals = [{ colorHex: '#F5F5F0' }, { colorHex: '#9A9A94' }];
  const colorful = [{ colorHex: '#C0392B' }, { colorHex: '#3E6FA8' }];
  const nStep = L.dayColorStep(neutrals);
  const cStep = L.dayColorStep(colorful);
  check('多件彩色比中性色色阶更高', cStep > nStep, `中性=${nStep} 彩色=${cStep}`);
  check('色阶在 0–4 范围', cStep >= 0 && cStep <= 4);

  // 归一化验证：同一件米色衬衫换光线（不同明度）不应导致大跳色
  const shirt1 = [{ colorHex: '#D8CFC0' }, { colorHex: '#4A4A48' }];
  const shirt2 = [{ colorHex: '#EDE6D8' }, { colorHex: '#3A3A38' }];
  const s1 = L.dayColorStep(shirt1);
  const s2 = L.dayColorStep(shirt2);
  check('同色不同光线色阶差 ≤ 1', Math.abs(s1 - s2) <= 1, `${s1} vs ${s2}`);
}

section('8. 完整度规则');
{
  const profileID = 'p5';
  const garments = [
    { id: 'a', profileID, layer: L.WearLayer.top, colorHex: '#FFFFFF', colorName: '白',
      material: 'cotton', fit: 'slim', occasions: ['通勤'], seasons: ['春'],
      wearCount: 0, lastWornDate: null, archived: false },
    { id: 'b', profileID, layer: L.WearLayer.bottom, colorHex: '#1C1C1E', colorName: '黑',
      material: 'cotton', fit: 'loose', occasions: ['通勤'], seasons: ['春'],
      wearCount: 0, lastWornDate: null, archived: false },
    { id: 'c', profileID, layer: L.WearLayer.shoes, colorHex: '#8B6A4E', colorName: '棕',
      material: 'leather', fit: 'regular', occasions: ['通勤'], seasons: ['春'],
      wearCount: 0, lastWornDate: null, archived: false },
  ];

  const results = L.recommend({
    garments, occasion: '通勤', season: '春', profileID, limit: 3,
  });
  const complete = results.find((r) => r.garments.length === 3);
  check('三件套被识别为「配齐了」',
    complete && complete.reasons.some((t) => t.includes('配齐了')));
  check('上窄下宽比例被识别',
    complete && complete.reasons.some((t) => t.includes('比例')));
}

section('8b. 分数区分度（回归测试）');
{
  const profileID = 'p5b';
  const garments = [
    { id: 'a', profileID, layer: L.WearLayer.top, colorHex: '#FFFFFF', colorName: '白',
      material: 'cotton', fit: 'slim', occasions: ['通勤'], seasons: ['春'],
      wearCount: 0, lastWornDate: null, archived: false },
    { id: 'b', profileID, layer: L.WearLayer.bottom, colorHex: '#1C1C1E', colorName: '黑',
      material: 'cotton', fit: 'loose', occasions: ['通勤'], seasons: ['春'],
      wearCount: 0, lastWornDate: null, archived: false },
    { id: 'c', profileID, layer: L.WearLayer.shoes, colorHex: '#8B6A4E', colorName: '棕',
      material: 'leather', fit: 'regular', occasions: ['通勤'], seasons: ['春'],
      wearCount: 0, lastWornDate: null, archived: false },
  ];

  const results = L.recommend({
    garments, occasion: '通勤', season: '春', profileID, limit: 5,
  });

  // ⚠️ 曾经用 min(score,100) 封顶，导致所有组合都是 100 分，
  // 「配齐三件」和「缺一件」得分相同，三件套被两件套挤掉。
  const scores = results.map((r) => r.score);
  const distinct = new Set(scores.map((s) => s.toFixed(2)));
  check('推荐分数有区分度', distinct.size > 1, `分数集合: ${[...distinct].join(', ')}`);
  check('分数不超过 100', scores.every((s) => s <= 100.01));
  check('分数不小于 0', scores.every((s) => s >= 0));

  // 三件套应排在两件套之前
  const threeIdx = results.findIndex((r) => r.garments.length === 3);
  const twoIdx = results.findIndex((r) => r.garments.length === 2);
  check('三件套排在两件套之前',
    threeIdx >= 0 && (twoIdx < 0 || threeIdx < twoIdx),
    `三件套第 ${threeIdx} 位，两件套第 ${twoIdx} 位`);

  const best = results[0];
  check('最高分组合配齐了三件',
    best.garments.length === 3 && best.reasons.some((t) => t.includes('配齐了')),
    `最高分组合 ${best.garments.length} 件`);
}

section('9. 材质对比规则');
{
  const profileID = 'p6';
  const garments = [
    { id: 'a', profileID, layer: L.WearLayer.top, colorHex: '#1C1C1E', colorName: '黑',
      material: 'knit', fit: 'regular', occasions: ['通勤'], seasons: ['春'],
      wearCount: 0, lastWornDate: null, archived: false },
    { id: 'b', profileID, layer: L.WearLayer.bottom, colorHex: '#1C1C1E', colorName: '黑',
      material: 'leather', fit: 'regular', occasions: ['通勤'], seasons: ['春'],
      wearCount: 0, lastWornDate: null, archived: false },
    { id: 'c', profileID, layer: L.WearLayer.shoes, colorHex: '#8B6A4E', colorName: '棕',
      material: 'leather', fit: 'regular', occasions: ['通勤'], seasons: ['春'],
      wearCount: 0, lastWornDate: null, archived: false },
  ];
  const results = L.recommend({ garments, occasion: '通勤', season: '春', profileID });
  check('产出推荐', results.length > 0);
  check('针织+皮革识别为材质对比',
    results[0] && results[0].reasons.some((t) => t.includes('材质有对比')),
    results[0] ? results[0].reasons.join(' / ') : '无结果');
}

section('10. 少于 3 件时不硬凑搭配');
{
  const profileID = 'p7';
  const garments = [
    { id: 'a', profileID, layer: L.WearLayer.top, colorHex: '#1C1C1E', colorName: '黑',
      material: 'cotton', fit: 'regular', occasions: ['通勤'], seasons: ['春'],
      wearCount: 0, lastWornDate: null, archived: false },
    { id: 'b', profileID, layer: L.WearLayer.bottom, colorHex: '#1C1C1E', colorName: '黑',
      material: 'cotton', fit: 'regular', occasions: ['通勤'], seasons: ['春'],
      wearCount: 0, lastWornDate: null, archived: false },
  ];
  const results = L.recommend({ garments, occasion: '通勤', season: '春', profileID });
  check('2 件衣服时不产出推荐（不硬凑）', results.length === 0);
}

// ─────────────────────────────────────────────

console.log('\n' + '─'.repeat(52));
console.log(`通过 ${passed} · 失败 ${failed}`);
if (failures.length > 0) {
  console.log('\n失败项:');
  failures.forEach((f) => console.log('  · ' + f));
}
console.log('─'.repeat(52));

process.exit(failed === 0 ? 0 : 1);
