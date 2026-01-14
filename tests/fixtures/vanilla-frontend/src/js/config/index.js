// src/js/config/index.js - Application configuration

const env = {
  get(key, defaultValue = '') {
    // In real app, would use build-time env vars
    return window.__ENV__?.[key] || defaultValue;
  },
};

export const config = {
  // API
  apiUrl: env.get('API_URL', 'http://localhost:8080/api/v1'),
  apiTimeout: parseInt(env.get('API_TIMEOUT', '30000'), 10),

  // App
  appName: env.get('APP_NAME', 'MyApp'),
  appVersion: env.get('APP_VERSION', '1.0.0'),
  environment: env.get('NODE_ENV', 'development'),

  // Auth
  accessTokenKey: 'access_token',
  refreshTokenKey: 'refresh_token',
  tokenRefreshThreshold: 5 * 60 * 1000, // 5 minutes before expiry

  // Features
  features: {
    darkMode: env.get('FEATURE_DARK_MODE', 'true') === 'true',
    notifications: env.get('FEATURE_NOTIFICATIONS', 'true') === 'true',
    analytics: env.get('FEATURE_ANALYTICS', 'false') === 'true',
  },

  // Pagination
  defaultPageSize: 20,
  maxPageSize: 100,

  // Validation
  validation: {
    usernameMinLength: 3,
    usernameMaxLength: 30,
    passwordMinLength: 8,
    bioMaxLength: 500,
  },

  // Helpers
  isDevelopment() {
    return this.environment === 'development';
  },

  isProduction() {
    return this.environment === 'production';
  },

  getApiUrl(path) {
    return `${this.apiUrl}${path}`;
  },
};
