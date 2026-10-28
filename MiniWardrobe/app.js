// ============================================================
// 家庭衣橱 · 小程序入口
//
// 全离线：不含任何网络请求代码。
// 照片存 wx.env.USER_DATA_PATH 文件区，库里只存相对路径。
// ============================================================

App({
  globalData: {
    // 当前档案 ID（单人使用时固定一个）
    currentProfileID: 'default',
    // 数据版本，用于迁移
    dataVersion: 1,
  },

  onLaunch() {
    // 初始化存储，检查是否需要迁移
    const store = require('./utils/store.js');
    store.init();

    const app = getApp();
    const profiles = store.getProfiles();
    if (profiles.length > 0) {
      app.globalData.currentProfileID = profiles[0].id;
    }
  },
});
