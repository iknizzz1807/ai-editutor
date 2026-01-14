// config/index.ts - Application configuration

export interface AppConfig {
  env: 'development' | 'staging' | 'production';
  apiBaseUrl: string;
  apiTimeout: number;
  auth: AuthConfig;
  features: FeatureFlags;
  analytics: AnalyticsConfig;
}

export interface AuthConfig {
  tokenStorageKey: string;
  refreshTokenStorageKey: string;
  tokenRefreshThreshold: number; // seconds before expiry to refresh
  maxRetries: number;
}

export interface FeatureFlags {
  enableDarkMode: boolean;
  enableNotifications: boolean;
  enableAnalytics: boolean;
  enableBetaFeatures: boolean;
  maintenanceMode: boolean;
}

export interface AnalyticsConfig {
  trackingId: string;
  enablePageViews: boolean;
  enableEvents: boolean;
  sampleRate: number;
}

const config: AppConfig = {
  env: (process.env.NODE_ENV as AppConfig['env']) || 'development',
  apiBaseUrl: process.env.REACT_APP_API_URL || 'http://localhost:3001',
  apiTimeout: 30000,
  auth: {
    tokenStorageKey: 'auth_token',
    refreshTokenStorageKey: 'refresh_token',
    tokenRefreshThreshold: 300,
    maxRetries: 3,
  },
  features: {
    enableDarkMode: true,
    enableNotifications: true,
    enableAnalytics: process.env.NODE_ENV === 'production',
    enableBetaFeatures: process.env.NODE_ENV !== 'production',
    maintenanceMode: false,
  },
  analytics: {
    trackingId: process.env.REACT_APP_ANALYTICS_ID || '',
    enablePageViews: true,
    enableEvents: true,
    sampleRate: 1.0,
  },
};

export default config;

export const isProduction = () => config.env === 'production';
export const isDevelopment = () => config.env === 'development';
export const getApiUrl = (path: string) => `${config.apiBaseUrl}${path}`;
