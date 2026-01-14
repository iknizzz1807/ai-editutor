// src/composables/useStorage.ts - Storage composable

import { ref, watch } from 'vue';

const PREFIX = 'myapp_';

export function useStorage(storage: Storage = localStorage) {
  function getKey(key: string): string {
    return `${PREFIX}${key}`;
  }

  function get<T>(key: string, defaultValue: T | null = null): T | null {
    try {
      const item = storage.getItem(getKey(key));
      return item ? JSON.parse(item) : defaultValue;
    } catch {
      return defaultValue;
    }
  }

  function set<T>(key: string, value: T): boolean {
    try {
      storage.setItem(getKey(key), JSON.stringify(value));
      return true;
    } catch {
      return false;
    }
  }

  function remove(key: string): void {
    storage.removeItem(getKey(key));
  }

  function clear(): void {
    const keysToRemove: string[] = [];
    for (let i = 0; i < storage.length; i++) {
      const key = storage.key(i);
      if (key?.startsWith(PREFIX)) {
        keysToRemove.push(key);
      }
    }
    keysToRemove.forEach((key) => storage.removeItem(key));
  }

  return { get, set, remove, clear };
}

// Reactive storage ref
export function useStorageRef<T>(key: string, defaultValue: T) {
  const storage = useStorage();
  const storedValue = storage.get<T>(key, defaultValue);
  const data = ref<T>(storedValue ?? defaultValue) as ReturnType<typeof ref<T>>;

  watch(
    data,
    (newValue) => {
      if (newValue === null || newValue === undefined) {
        storage.remove(key);
      } else {
        storage.set(key, newValue);
      }
    },
    { deep: true }
  );

  return data;
}
