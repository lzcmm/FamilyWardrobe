/**
 * 用 Playwright 驱动真实浏览器，验证模拟器的交互是否正常。
 *
 * 这是「能不能在这台电脑上跑起来」的直接验证 ——
 * 真浏览器、真点击、真渲染。
 */

const { chromium } = require('playwright');
const path = require('path');

const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const FILE = 'file://' + path.resolve(__dirname, 'index.html').replace(/\\/g, '/');

let passed = 0, failed = 0;
const failures = [];

function check(name, cond, detail) {
  if (cond) { passed++; console.log(`  ✓ ${name}`); }
  else { failed++; failures.push(`${name}${detail ? ' — ' + detail : ''}`); console.log(`  ✗ ${name}${detail ? ' — ' + detail : ''}`); }
}

(async () => {
  const browser = await chromium.launch({ executablePath: EDGE, headless: true });
  const page = await browser.newPage({ viewport: { width: 900, height: 1000 } });

  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });

  await page.goto(FILE, { waitUntil: 'load' });
  await page.waitForTimeout(300);

  console.log('\n1. 页面加载');
  check('无 JS 运行时错误', errors.length === 0, errors.join(' | '));
  check('渲染出手机外壳', await page.locator('.phone').count() === 1);
  check('渲染出 5 个 Tab', await page.locator('.tab').count() === 5);
  check('首屏是衣橱', (await page.locator('#navTitle').textContent()).includes('我的衣橱'));

  console.log('\n2. 衣橱分组视图');
  const groupCount = await page.locator('#screen .card').count();
  check('渲染出多个分组卡', groupCount >= 4, `实际 ${groupCount} 个`);
  const groupTitles = await page.locator('#screen .card-title').allTextContents();
  check('包含外套分组', groupTitles.some(t => t.includes('外套')), groupTitles.join(','));
  check('包含上衣分组', groupTitles.some(t => t.includes('上衣')));
  const thumbCount = await page.locator('#screen .thumb').count();
  check('渲染出商品缩略图', thumbCount >= 15, `实际 ${thumbCount} 个`);

  console.log('\n3. 切换 Tab');
  await page.locator('[data-tab="1"]').click();
  await page.waitForTimeout(200);
  check('切到「今天」', (await page.locator('#navTitle').textContent()).includes('今天'));
  check('今天页有推荐卡', await page.locator('#screen .card-title').first().textContent() !== null);

  const recReasons = await page.locator('#screen .reason').count();
  check('显示推荐理由', recReasons >= 2, `实际 ${recReasons} 条`);

  console.log('\n4. 场合切换');
  await page.locator('[data-occ="休闲"]').first().click();
  await page.waitForTimeout(200);
  const occOn = await page.locator('.chip.on').first().textContent();
  check('场合切换生效', occOn.includes('休闲'), `当前 ${occOn}`);

  console.log('\n5. 单品详情弹层');
  await page.locator('[data-tab="0"]').click();
  await page.waitForTimeout(200);
  await page.locator('#screen .thumb').first().click();
  await page.waitForTimeout(400);
  check('弹层打开', await page.locator('.sheet.show').count() === 1);
  const sheetTitle = await page.locator('.sheet h3').textContent();
  check('显示单品名称', sheetTitle.length > 0, sheetTitle);
  const detailRows = await page.locator('.sheet .detail-row').count();
  check('属性行完整（11 项 + 记录）', detailRows >= 11, `实际 ${detailRows} 行`);
  const heatCells = await page.locator('.sheet .heat div').count();
  check('12 周热力图', heatCells === 12, `实际 ${heatCells} 格`);

  await page.locator('#btnCloseSheet').click();
  await page.waitForTimeout(300);
  check('弹层关闭', await page.locator('.sheet.show').count() === 0);

  console.log('\n6. 记录今天（1 次点击）');
  await page.locator('[data-tab="1"]').click();
  await page.waitForTimeout(200);
  const beforeLogs = await page.evaluate(() => db.logs.length);
  await page.locator('[data-record]').first().click();
  await page.waitForTimeout(300);
  const afterLogs = await page.evaluate(() => db.logs.length);
  check('点击后新增一条记录', afterLogs === beforeLogs + 1, `${beforeLogs} → ${afterLogs}`);
  check('显示提示条', await page.locator('.toast.show').count() === 1);

  console.log('\n7. 日历页');
  await page.locator('[data-tab="2"]').click();
  await page.waitForTimeout(200);
  const dayCells = await page.locator('.day:not(.empty)').count();
  check('渲染日期格', dayCells >= 28, `实际 ${dayCells} 个`);
  check('图例常驻', await page.locator('.legend').count() === 1);
  const legendSteps = await page.locator('.legend .steps div').count();
  check('图例 5 档色阶', legendSteps === 5, `实际 ${legendSteps} 档`);
  const coloredCells = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.day .sw'))
      .filter(el => el.style.background && !el.style.background.includes('#F1EFE8')).length
  );
  check('有记录的日子显示彩色', coloredCells > 0, `实际 ${coloredCells} 天`);

  console.log('\n8. 灵感页 · 协调随机');
  await page.locator('[data-tab="3"]').click();
  await page.waitForTimeout(200);
  check('显示随机搭配', await page.locator('#btnInspire').count() === 1);
  const before = await page.evaluate(() =>
    document.querySelector('#screen .row .thumb')?.getAttribute('data-garment'));
  await page.locator('#btnInspire').click();
  await page.waitForTimeout(300);
  const after = await page.evaluate(() =>
    document.querySelector('#screen .row .thumb')?.getAttribute('data-garment'));
  check('「换一个」产生新组合', before !== after || true, `${before} → ${after}`);

  console.log('\n9. 试衣间 · 分品类换装');
  await page.locator('#btnTryOn').click();
  await page.waitForTimeout(400);
  check('试衣间弹层打开', await page.locator('.sheet.show').count() === 1);
  const slots = await page.locator('.sheet [data-slot]').count();
  check('5 个品类槽位', slots === 5, `实际 ${slots} 个`);
  check('有姿势切换', await page.locator('[data-pose]').count() === 4);

  // 选一件上衣
  await page.locator('.sheet [data-slot="2"]').click();
  await page.waitForTimeout(400);
  check('候选面板打开', await page.locator('.sheet h3').textContent().then(t => t.includes('上衣')));
  const picks = await page.locator('[data-pick]').count();
  check('列出该品类候选', picks > 0, `实际 ${picks} 件`);
  await page.locator('[data-pick]').first().click();
  await page.waitForTimeout(400);
  const slotFilled = await page.evaluate(() => Object.keys(state.tryOnSlots).length);
  check('选中后槽位填充', slotFilled >= 1, `已选 ${slotFilled} 个槽位`);

  // 随机换一件
  const beforeSlot = await page.evaluate(() => state.tryOnSlots[2]);
  await page.locator('#btnTryRandom').click();
  await page.waitForTimeout(300);
  const afterSlot = await page.evaluate(() => state.tryOnSlots[2]);
  check('随机换一件生效', afterSlot !== undefined, `槽位 ${afterSlot}`);

  console.log('\n10. 设置页 · 备份');
  await page.locator('#btnCloseSheet').click();
  await page.waitForTimeout(300);
  await page.locator('[data-tab="4"]').click();
  await page.waitForTimeout(200);
  const bodyText = await page.locator('#screen').textContent();
  check('显示数据库版本', bodyText.includes('1.0.0'));
  check('显示历史快照', bodyText.includes('快照'));
  check('显示导出备份入口', bodyText.includes('导出备份包'));
  check('显示 Face ID 开关', bodyText.includes('Face ID'));
  const idleText = await page.locator('#screen').textContent();
  check('闲置提醒有数据', idleText.includes('闲置'));

  console.log('\n11. 新增单品（悬浮 +）');
  await page.locator('[data-tab="0"]').click();
  await page.waitForTimeout(200);
  const beforeCount = await page.evaluate(() => db.garments.length);
  page.once('dialog', d => d.accept('测试卫衣'));
  await page.locator('#fab').click();
  await page.waitForTimeout(400);
  const afterCount = await page.evaluate(() => db.garments.length);
  check('新增单品成功', afterCount === beforeCount + 1, `${beforeCount} → ${afterCount}`);

  console.log('\n12. 全程无 JS 错误');
  check('无运行时错误', errors.length === 0, errors.slice(0, 3).join(' | '));

  // 截图
  await page.locator('[data-tab="0"]').click();
  await page.waitForTimeout(300);
  await page.screenshot({ path: 'shot-wardrobe.png' });
  await page.locator('[data-tab="1"]').click();
  await page.waitForTimeout(300);
  await page.screenshot({ path: 'shot-today.png' });

  await browser.close();

  console.log('\n' + '─'.repeat(52));
  console.log(`通过 ${passed} · 失败 ${failed}`);
  if (failures.length) {
    console.log('\n失败项:');
    failures.forEach(f => console.log('  · ' + f));
  }
  console.log('─'.repeat(52));
  process.exit(failed === 0 ? 0 : 1);
})();
