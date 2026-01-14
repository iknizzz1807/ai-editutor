// src/js/api/client.js - HTTP client for API requests

import { config } from '../config/index.js';
import { storage } from '../utils/storage.js';

class ApiClient {
  constructor(baseUrl) {
    this.baseUrl = baseUrl || config.apiUrl;
    this.defaultHeaders = {
      'Content-Type': 'application/json',
    };
  }

  // Q: How should we implement request interceptors for automatic token refresh?
  async request(endpoint, options = {}) {
    const url = `${this.baseUrl}${endpoint}`;

    const headers = {
      ...this.defaultHeaders,
      ...options.headers,
    };

    // Add auth token if available
    const token = storage.get('access_token');
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    try {
      const response = await fetch(url, {
        ...options,
        headers,
      });

      // Handle token expiration
      if (response.status === 401) {
        const refreshed = await this.refreshToken();
        if (refreshed) {
          // Retry original request
          headers['Authorization'] = `Bearer ${storage.get('access_token')}`;
          return fetch(url, { ...options, headers });
        }
        throw new AuthError('Session expired');
      }

      if (!response.ok) {
        const error = await response.json();
        throw new ApiError(error.message || 'Request failed', response.status, error);
      }

      return response.json();
    } catch (error) {
      if (error instanceof ApiError || error instanceof AuthError) {
        throw error;
      }
      throw new NetworkError('Network error', error);
    }
  }

  async get(endpoint, params = {}) {
    const queryString = new URLSearchParams(params).toString();
    const url = queryString ? `${endpoint}?${queryString}` : endpoint;
    return this.request(url, { method: 'GET' });
  }

  async post(endpoint, data) {
    return this.request(endpoint, {
      method: 'POST',
      body: JSON.stringify(data),
    });
  }

  async put(endpoint, data) {
    return this.request(endpoint, {
      method: 'PUT',
      body: JSON.stringify(data),
    });
  }

  async patch(endpoint, data) {
    return this.request(endpoint, {
      method: 'PATCH',
      body: JSON.stringify(data),
    });
  }

  async delete(endpoint) {
    return this.request(endpoint, { method: 'DELETE' });
  }

  async refreshToken() {
    const refreshToken = storage.get('refresh_token');
    if (!refreshToken) {
      return false;
    }

    try {
      const response = await fetch(`${this.baseUrl}/auth/refresh`, {
        method: 'POST',
        headers: this.defaultHeaders,
        body: JSON.stringify({ refresh_token: refreshToken }),
      });

      if (!response.ok) {
        storage.remove('access_token');
        storage.remove('refresh_token');
        return false;
      }

      const data = await response.json();
      storage.set('access_token', data.access_token);
      storage.set('refresh_token', data.refresh_token);
      return true;
    } catch {
      return false;
    }
  }
}

// Custom error classes
class ApiError extends Error {
  constructor(message, status, data) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.data = data;
  }
}

class AuthError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AuthError';
  }
}

class NetworkError extends Error {
  constructor(message, cause) {
    super(message);
    this.name = 'NetworkError';
    this.cause = cause;
  }
}

export const apiClient = new ApiClient();
export { ApiError, AuthError, NetworkError };
