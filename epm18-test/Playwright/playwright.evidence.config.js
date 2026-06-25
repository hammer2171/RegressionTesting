const baseConfig = require('./playwright.config');

module.exports = {
  ...baseConfig,
  use: {
    ...baseConfig.use,
    trace: 'on',
    screenshot: 'on',
    video: 'on',
  },
};
