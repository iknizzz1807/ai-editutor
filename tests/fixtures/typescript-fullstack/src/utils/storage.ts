// utils/storage.ts - Browser storage utilities

import config from '../config';
import { AuthTokens } from '../types/auth';

export type StorageType = 'local' | 'session';

export interface StorageOptions {
  type?: StorageType;
  encrypt?: boolean;
  expiresIn?: number; // seconds
}

interface StoredItem<T> {
  value: T;
  expiresAt?: number;
}

function getStorage(type: StorageType): Storage {
  return type === 'local' ? localStorage : sessionStorage;
}

export function setItem<T>(
  key: string,
  value: T,
  options: StorageOptions = {}
): void {
  const { type = 'local', expiresIn } = options;
  const storage = getStorage(type);

  const item: StoredItem<T> = {
    value,
    expiresAt: expiresIn ? Date.now() + expiresIn * 1000 : undefined,
  };

  try {
    storage.setItem(key, JSON.stringify(item));
  } catch (error) {
    console.error(`Failed to store item: ${key}`, error);
  }
}

export function getItem<T>(key: string, options: StorageOptions = {}): T | null {
  const { type = 'local' } = options;
  const storage = getStorage(type);

  try {
    const raw = storage.getItem(key);
    if (!raw) return null;

    const item: StoredItem<T> = JSON.parse(raw);

    if (item.expiresAt && Date.now() > item.expiresAt) {
      removeItem(key, options);
      return null;
    }

    return item.value;
  } catch (error) {
    console.error(`Failed to retrieve item: ${key}`, error);
    return null;
  }
}

export function removeItem(key: string, options: StorageOptions = {}): void {
  const { type = 'local' } = options;
  const storage = getStorage(type);
  storage.removeItem(key);
}

export function clearAll(type: StorageType = 'local'): void {
  const storage = getStorage(type);
  storage.clear();
}

// Auth token specific helpers
export function saveAuthTokens(tokens: AuthTokens): void {
  setItem(config.auth.tokenStorageKey, tokens.accessToken);
  setItem(config.auth.refreshTokenStorageKey, tokens.refreshToken);
}

export function getAccessToken(): string | null {
  return getItem<string>(config.auth.tokenStorageKey);
}

export function getRefreshToken(): string | null {
  return getItem<string>(config.auth.refreshTokenStorageKey);
}

export function clearAuthTokens(): void {
  removeItem(config.auth.tokenStorageKey);
  removeItem(config.auth.refreshTokenStorageKey);
}

export function hasValidTokens(): boolean {
  const accessToken = getAccessToken();
  const refreshToken = getRefreshToken();
  return Boolean(accessToken && refreshToken);
}
