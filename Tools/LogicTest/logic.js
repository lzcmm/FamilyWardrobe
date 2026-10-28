/**
 * 核心业务逻辑的 JS 等价实现
 *
 * 目的：本机没有 Xcode，无法编译 Swift。但推荐引擎、Lab 取色、层级顺序
 * 这些是**纯算法**，不依赖 UIKit/SwiftData。移植成 JS 后可以在 Node 上
 * 跑真实测试，验证算法逻辑正确。
 *
 * ⚠️ 本文件不是 App 的运行代码，是**验证工具**。Swift 版才是产品代码，
 *    两者必须保持算法一致（改一处要改两处）。
 *    对应 Swift 源文件：
 *      RecommendationEngine.swift  →  recommend() / inspire() / evaluate*()
 *      WearLogService.swift         →  DayColorScale
 *      Enums.swift                  →  WearLayer
 */

// ─────────────────────────────────────────────
// 枚举（对应 Enums.swift）
// ─────────────────────────────────────────────

const WearLayer = {
  headwear: 0,
  neckwear: 1,
  top: 2,
  dress: 3,
  outerwear: 4,
  bottom: 5,
  shoes: 6,
  acc: 7,
  bag: 8,
};

const LAYER_ORDER = [0, 1, 2, 3, 4, 5, 6, 7, 8];

const LAYER_NAMES = {
  0: '头饰', 1: '围巾', 2: '上衣', 3: '连衣裙',
  4: '外套', 5: '下装', 6: '鞋履', 7: '配饰', 8: '包袋',
};

/** 连衣裙覆盖上衣与下装两层 */
function coversLayers(layer) {
  return layer === WearLayer.dress ? [WearLayer.top, WearLayer.bottom] : [];
}

/**
 * 合成遮挡顺序（由后到前）。
 * 必须由枚举派生，不能手写 —— 加 bag 层时手写过，漏了。
 */
function overlayOrder() {
  return [...LAYER_ORDER].reverse();
}

// ─────────────────────────────────────────────
// Lab 颜色转换（对应 WearLogService.swift）
// ─────────────────────────────────────────────

function srgbToLab(r, g, b) {
  const linearize = (c) => {
    const v = c / 255.0;
    return v > 0.04045 ? Math.pow((v + 0.055) / 1.055, 2.4) : v / 12.92;
  };

  const lr = linearize(r);
  const lg = linearize(g);
  const lb = linearize(b);

  const x = (lr * 0.4124 + lg * 0.3576 + lb * 0.1805) / 0.95047;
  const y = (lr * 0.2126 + lg * 0.7152 + lb * 0.0722) / 1.00000;
  const z = (lr * 0.0193 + lg * 0.1192 + lb * 0.9505) / 1.08883;

  const f = (t) => (t > 0.008856 ? Math.pow(t, 1 / 3) : 7.787 * t + 16.0 / 116.0);

  const fx = f(x);
  const fy = f(y);
  const fz = f(z);

  return {
    L: 116.0 * fy - 16.0,
    a: 500.0 * (fx - fy),
    b: 200.0 * (fy - fz),
  };
}

function hexToRgb(hex) {
  let cleaned = hex.trim();
  if (cleaned.startsWith('#')) cleaned = cleaned.slice(1);
  const v = parseInt(cleaned, 16);
  return { r: (v >> 16) & 0xFF, g: (v >> 8) & 0xFF, b: v & 0xFF };
}

/**
 * 日历色阶（0–4）。
 * 规则：当天 3–4 件取 Lab 均值 → 映射到 5 档。
 * 记录不足 2 件不参与取色，返回 0。
 */
function dayColorStep(garments) {
  if (garments.length < 2) return 0;

  const labs = garments
    .map((item) => {
      const rgb = hexToRgb(item.colorHex);
      return srgbToLab(rgb.r, rgb.g, rgb.b);
    })
    .filter(Boolean);

  if (labs.length === 0) return 0;

  const meanL = labs.reduce((s, v) => s + v.L, 0) / labs.length;
  const meanA = labs.reduce((s, v) => s + v.a, 0) / labs.length;
  const meanB = labs.reduce((s, v) => s + v.b, 0) / labs.length;

  // 彩度：Lab 平面上的半径
  const chroma = Math.sqrt(meanA * meanA + meanB * meanB);

  if (chroma < 8) return 0;
  if (chroma < 18) return 1;
  if (chroma < 32) return 2;
  if (chroma < 50) return 3;
  return 4;
}

// ─────────────────────────────────────────────
// 推荐引擎（对应 RecommendationEngine.swift）
// ─────────────────────────────────────────────

const DEFAULT_WEIGHTS = {
  colorHarmony: 25,
  proportion: 20,
  materialContrast: 15,
  completeness: 20,
  freshness: 10,
  preference: 10,
};

const baseTotal = (w) =>
  w.colorHarmony + w.proportion + w.materialContrast +
  w.completeness + w.freshness + w.preference;

/**
 * 各项加分的理论最大值之和。
 * 原始分 = 基础分 + 加分 - 扣分，会超过 100。
 * 直接 min(score,100) 会把所有高分组合削平成 100 ——
 * 「配齐三件」和「缺一件」得分相同，推荐失去区分度。
 */
const MAX_BONUS_TOTAL = 39;

function normalized(rawScore, weights) {
  const maxRaw = baseTotal(weights) + MAX_BONUS_TOTAL;
  if (maxRaw <= 0) return 0;
  return Math.max(0, Math.min(100, rawScore / maxRaw * 100));
}

const MATERIALS = {
  cotton: { name: '棉', glossy: false, textured: false },
  linen: { name: '麻', glossy: false, textured: false },
  wool: { name: '羊毛', glossy: false, textured: true },
  silk: { name: '丝', glossy: true, textured: false },
  polyester: { name: '涤纶', glossy: true, textured: false },
  denim: { name: '牛仔', glossy: false, textured: true },
  leather: { name: '皮革', glossy: true, textured: false },
  knit: { name: '针织', glossy: false, textured: true },
  down: { name: '羽绒', glossy: false, textured: true },
};

/** 判断颜色属性 */
function guessColor(garment) {
  const rgb = hexToRgb(garment.colorHex);
  const maxC = Math.max(rgb.r, rgb.g, rgb.b);
  const minC = Math.min(rgb.r, rgb.g, rgb.b);
  const luminance = (0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b) / 255.0;

  return {
    name: garment.colorName || '未分类',
    isBright: luminance > 0.72,
    isNeutral: maxC - minC < 32,
  };
}

/**
 * 候选池过滤。
 *
 * ⚠️ 逐项判断，**不要用 && / || 混写** ——
 * && 优先级高于 ||，混写会导致「非当前档案的单品」混入池子。
 * 这是家人共用场景的数据隔离漏洞。
 */
function buildPool(garments, profileID, occasion, season) {
  return garments.filter((garment) => {
    if (garment.profileID !== profileID) return false;
    if (garment.archived) return false;
    if (garment.seasons.length > 0 && !garment.seasons.includes(season)) return false;
    if (garment.occasions.length > 0 && !garment.occasions.includes(occasion)) return false;
    return true;
  });
}

/** 色彩和谐：全身主色 ≤ 3，亮色只允许一处 */
function evaluateColor(garments, weights) {
  const colors = garments.map(guessColor);
  if (colors.length === 0) return { score: 0, text: null };

  const distinct = new Set(colors.map((c) => c.name));
  let score = weights.colorHarmony;
  let text = null;

  if (distinct.size <= 3) {
    text = `全身仅 ${distinct.size} 个主色`;
  } else {
    score -= (distinct.size - 3) * 8;
    text = `有 ${distinct.size} 个主色，偏多`;
  }

  const brightCount = colors.filter((c) => c.isBright).length;
  if (brightCount > 1) score -= (brightCount - 1) * 6;

  if (colors.some((c) => c.isNeutral)) score += 3;

  return { score: Math.max(0, score), text };
}

/** 比例：上短下长 / 宽窄对比 */
function evaluateProportion(garments, weights) {
  const layers = new Set(garments.map((g) => g.layer));
  let score = weights.proportion;
  let text = null;

  const hasTop = layers.has(WearLayer.top) || layers.has(WearLayer.dress);
  const hasBottom = layers.has(WearLayer.bottom);

  if (hasTop && hasBottom) {
    const top = garments.find((g) => g.layer === WearLayer.top || g.layer === WearLayer.dress);
    const bottom = garments.find((g) => g.layer === WearLayer.bottom);
    if (top && bottom) {
      if (top.fit === 'slim' && bottom.fit === 'loose') {
        score += 6;
        text = '上窄下宽，比例拉长';
      } else if (top.fit === 'oversized' && bottom.fit === 'slim') {
        score += 4;
        text = '上宽下窄，有廓形对比';
      } else {
        text = '上下装型接近';
      }
    }
  }

  if (layers.has(WearLayer.outerwear) && hasBottom) score += 2;

  return { score: Math.max(0, score), text };
}

/** 材质对比：粗针织配光泽面料 */
function evaluateMaterial(garments, weights) {
  const materials = garments.map((g) => MATERIALS[g.material] || MATERIALS.cotton);
  let score = weights.materialContrast;
  let text = null;

  const hasTextured = materials.some((m) => m.textured);
  const hasGlossy = materials.some((m) => m.glossy);

  if (hasTextured && hasGlossy) {
    score += 6;
    text = '粗糙料配光泽面，材质有对比';
  } else if (!hasTextured && !hasGlossy) {
    text = '全身质地统一';
  } else {
    text = '材质偏单一';
  }

  if (materials.filter((m) => m.name === '针织').length >= 2) score -= 5;

  return { score: Math.max(0, score), text };
}

/** 完整度：通勤必须「上装 + 下装 + 正装鞋」 */
function evaluateCompleteness(garments, weights) {
  const layers = new Set(garments.map((g) => g.layer));
  let score = weights.completeness;
  let text = null;

  const hasTop = layers.has(WearLayer.top) || layers.has(WearLayer.dress);
  const hasBottom = layers.has(WearLayer.bottom) || layers.has(WearLayer.dress);
  const hasShoes = layers.has(WearLayer.shoes);

  if (hasTop && hasBottom && hasShoes) {
    score += 8;
    text = '上装 + 下装 + 鞋，配齐了';
  } else {
    const missing = [];
    if (!hasTop) missing.push('上衣');
    if (!hasBottom) missing.push('下装');
    if (!hasShoes) missing.push('鞋');
    score -= missing.length * 6;
    text = `还缺 ${missing.join('、')}`;
  }

  return { score: Math.max(0, score), text };
}

/** 新鲜度：7 天内不重复；闲置 90 天以上额外加分 */
function evaluateFreshness(garments, recentIDs, weights) {
  let score = weights.freshness;
  let text = null;

  const recentHits = garments.filter((g) => recentIDs.has(g.id)).length;
  if (recentHits > 0) {
    score -= recentHits * 15;
    text = `有 ${recentHits} 件最近穿过`;
  }

  const idle = garments.filter((g) => {
    if (!g.lastWornDate) return true;
    const days = (Date.now() - new Date(g.lastWornDate).getTime()) / 86400000;
    return days > 90;
  });

  if (idle.length > 0) {
    score += idle.length * 4;
    if (!text) {
      text = `${idle.map((g) => g.name).join('、')} 90 天未穿，一并唤醒`;
    }
  }

  return { score: Math.max(0, score), text };
}

/** 偏好匹配：场合一致 */
function evaluatePreference(garments, occasion, weights) {
  let score = weights.preference;
  let text = null;

  const matched = garments.filter((g) => g.occasions.includes(occasion)).length;
  if (matched === garments.length && garments.length > 0) {
    score += 8;
    text = `全部单品都适合${occasion}`;
  } else if (matched > 0) {
    score += matched * 2;
  }

  return { score: Math.max(0, score), text };
}

/** 给一套组合打分 */
function evaluate(combination, occasion, recentIDs, weights) {
  let score = 0;
  const reasons = [];

  const dims = [
    evaluateColor(combination, weights),
    evaluateProportion(combination, weights),
    evaluateMaterial(combination, weights),
    evaluateCompleteness(combination, weights),
    evaluateFreshness(combination, recentIDs, weights),
    evaluatePreference(combination, occasion, weights),
  ];

  for (const dim of dims) {
    score += dim.score;
    if (dim.text) reasons.push(dim.text);
  }

  return { garments: combination, score: normalized(score, weights), reasons };
}

/**
 * 生成推荐。
 * 组合数控制：先按层分桶取前 N 个候选，再组合，避免百万级组合。
 */
function recommend({
  garments,
  occasion,
  season,
  profileID,
  recentIDs = new Set(),
  maxCandidates = 12,
  limit = 5,
  weights = DEFAULT_WEIGHTS,
}) {
  const pool = buildPool(garments, profileID, occasion, season);
  if (pool.length < 3) return [];

  const buckets = {};
  for (const layer of LAYER_ORDER) {
    const items = pool
      .filter((g) => g.layer === layer)
      .sort((a, b) => b.wearCount - a.wearCount);
    if (items.length > 0) buckets[layer] = items.slice(0, maxCandidates);
  }

  const tops = buckets[WearLayer.top] || [];
  const bottoms = buckets[WearLayer.bottom] || [];
  const dresses = buckets[WearLayer.dress] || [];
  const outers = buckets[WearLayer.outerwear] || [];
  const shoes = buckets[WearLayer.shoes] || [];

  const candidates = [];
  for (const top of tops) {
    for (const bottom of bottoms) {
      candidates.push([top, bottom]);
      for (const shoe of shoes.slice(0, 4)) candidates.push([top, bottom, shoe]);
      for (const outer of outers.slice(0, 4)) {
        candidates.push([top, outer, bottom]);
        for (const shoe of shoes.slice(0, 2)) {
          candidates.push([top, outer, bottom, shoe]);
        }
      }
    }
  }
  for (const dress of dresses) {
    candidates.push([dress]);
    for (const outer of outers.slice(0, 4)) candidates.push([dress, outer]);
    for (const shoe of shoes.slice(0, 4)) candidates.push([dress, shoe]);
    for (const outer of outers.slice(0, 4)) {
      for (const shoe of shoes.slice(0, 2)) candidates.push([dress, outer, shoe]);
    }
  }

  if (candidates.length === 0) return [];

  const scored = candidates.map((c) => evaluate(c, occasion, recentIDs, weights));
  scored.sort((a, b) => b.score - a.score);

  // 去重：同一层不出现两件
  const deduped = [];
  for (const candidate of scored) {
    const isDuplicate = deduped.some((existing) => {
      const existingIDs = new Set(existing.garments.map((g) => g.id));
      const candidateIDs = new Set(candidate.garments.map((g) => g.id));
      const overlap = [...existingIDs].some((id) => candidateIDs.has(id));
      const sameLayerSet =
        existing.garments.map((g) => g.layer).sort().join() ===
        candidate.garments.map((g) => g.layer).sort().join();
      return overlap && sameLayerSet;
    });
    if (!isDuplicate) deduped.push(candidate);
    if (deduped.length >= limit) break;
  }

  return deduped;
}

/**
 * 协调随机 —— 在规则打分后的可行解空间内做加权随机。
 * 纯随机的结果九成不能穿出门，用户试两次就放弃。
 */
function inspire({
  garments,
  occasion,
  season,
  profileID,
  recentIDs = new Set(),
  count = 1,
  weights = DEFAULT_WEIGHTS,
  rng = Math.random,
}) {
  const scored = recommend({
    garments, occasion, season, profileID, recentIDs,
    limit: 30, weights,
  });
  if (scored.length === 0) return [];

  const results = [];
  const used = new Set();

  for (let i = 0; i < count; i++) {
    const weightsArr = scored.map((rec) => {
      const base = Math.max(0.01, rec.score / 100);
      const idleBonus = rec.garments.reduce((sum, g) => {
        if (!g.lastWornDate) return sum + 0.5;
        const days = (Date.now() - new Date(g.lastWornDate).getTime()) / 86400000;
        return sum + Math.min(days / 30, 2) * 0.15;
      }, 0);
      return base * (1 + idleBonus);
    });

    const total = weightsArr.reduce((s, v) => s + v, 0);
    let threshold = rng() * total;
    let chosen = scored[scored.length - 1];
    for (let j = 0; j < scored.length; j++) {
      threshold -= weightsArr[j];
      if (threshold <= 0) { chosen = scored[j]; break; }
    }

    const signature = chosen.garments.map((g) => g.id).sort().join();
    if (used.has(signature)) continue;
    used.add(signature);
    results.push(chosen);
  }

  return results;
}

// 同时兼容 Node (CommonJS) 与浏览器 (全局)
const API = {
  WearLayer,
  LAYER_ORDER,
  LAYER_NAMES,
  coversLayers,
  overlayOrder,
  srgbToLab,
  hexToRgb,
  dayColorStep,
  buildPool,
  recommend,
  inspire,
  evaluate,
  normalized,
  baseTotal,
  MAX_BONUS_TOTAL,
  DEFAULT_WEIGHTS,
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = API;
} else {
  window.L = API;
}
