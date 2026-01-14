// src/js/utils/storage.js - Storage utilities

class Storage {
  constructor(prefix = 'app_') {
    this.prefix = prefix;
    this.storage = window.localStorage;
  }

  getKey(key) {
    return `${this.prefix}${key}`;
  }

  get(key, defaultValue = null) {
    try {
      const item = this.storage.getItem(this.getKey(key));
      if (item === null) {
        return defaultValue;
      }
      return JSON.parse(item);
    } catch {
      return defaultValue;
    }
  }

  set(key, value) {
    try {
      this.storage.setItem(this.getKey(key), JSON.stringify(value));
      return true;
    } catch (error) {
      console.error('Storage error:', error);
      return false;
    }
  }

  remove(key) {
    this.storage.removeItem(this.getKey(key));
  }

  clear() {
    // Only clear items with our prefix
    const keys = [];
    for (let i = 0; i < this.storage.length; i++) {
      const key = this.storage.key(i);
      if (key && key.startsWith(this.prefix)) {
        keys.push(key);
      }
    }
    keys.forEach((key) => this.storage.removeItem(key));
  }

  // Q: How should we handle storage quota exceeded errors?
  setWithExpiry(key, value, ttlMs) {
    const item = {
      value,
      expiry: Date.now() + ttlMs,
    };
    return this.set(key, item);
  }

  getWithExpiry(key, defaultValue = null) {
    const item = this.get(key);
    if (!item) {
      return defaultValue;
    }

    if (Date.now() > item.expiry) {
      this.remove(key);
      return defaultValue;
    }

    return item.value;
  }

  // Session storage wrapper
  session = {
    storage: window.sessionStorage,
    prefix: this.prefix,

    get(key, defaultValue = null) {
      try {
        const item = this.storage.getItem(`${this.prefix}${key}`);
        return item ? JSON.parse(item) : defaultValue;
      } catch {
        return defaultValue;
      }
    },

    set(key, value) {
      try {
        this.storage.setItem(`${this.prefix}${key}`, JSON.stringify(value));
        return true;
      } catch {
        return false;
      }
    },

    remove(key) {
      this.storage.removeItem(`${this.prefix}${key}`);
    },

    clear() {
      const keys = [];
      for (let i = 0; i < this.storage.length; i++) {
        const key = this.storage.key(i);
        if (key && key.startsWith(this.prefix)) {
          keys.push(key);
        }
      }
      keys.forEach((k) => this.storage.removeItem(k));
    },
  };
}

export const storage = new Storage('myapp_');
