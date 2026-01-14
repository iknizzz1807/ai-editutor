// api/client.ts - HTTP client with interceptors and error handling

import config, { getApiUrl } from '../config';
import { ApiResponse, ApiError, RequestConfig, HttpMethod } from '../types/api';
import { getAccessToken, getRefreshToken, saveAuthTokens, clearAuthTokens } from '../utils/storage';
import { RefreshTokenResponse } from '../types/auth';

class ApiClient {
  private baseUrl: string;
  private timeout: number;
  private isRefreshing: boolean = false;
  private refreshPromise: Promise<string> | null = null;

  constructor() {
    this.baseUrl = config.apiBaseUrl;
    this.timeout = config.apiTimeout;
  }

  private async getHeaders(customHeaders?: Record<string, string>): Promise<Headers> {
    const headers = new Headers({
      'Content-Type': 'application/json',
      ...customHeaders,
    });

    const token = getAccessToken();
    if (token) {
      headers.set('Authorization', `Bearer ${token}`);
    }

    return headers;
  }

  // Q: How does this refresh token logic prevent race conditions when multiple requests fail simultaneously?
  private async refreshAccessToken(): Promise<string> {
    if (this.isRefreshing && this.refreshPromise) {
      return this.refreshPromise;
    }

    this.isRefreshing = true;
    this.refreshPromise = new Promise(async (resolve, reject) => {
      try {
        const refreshToken = getRefreshToken();
        if (!refreshToken) {
          throw new Error('No refresh token available');
        }

        const response = await fetch(`${this.baseUrl}/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refreshToken }),
        });

        if (!response.ok) {
          throw new Error('Failed to refresh token');
        }

        const data: RefreshTokenResponse = await response.json();
        saveAuthTokens({
          accessToken: data.accessToken,
          refreshToken: refreshToken,
          expiresIn: data.expiresIn,
          tokenType: 'Bearer',
        });

        resolve(data.accessToken);
      } catch (error) {
        clearAuthTokens();
        reject(error);
      } finally {
        this.isRefreshing = false;
        this.refreshPromise = null;
      }
    });

    return this.refreshPromise;
  }

  private async handleResponse<T>(response: Response): Promise<T> {
    if (response.status === 401) {
      try {
        await this.refreshAccessToken();
        // Retry would happen at the calling level
        throw { code: 'TOKEN_REFRESHED', message: 'Token refreshed, retry request' };
      } catch (error) {
        throw { code: 'UNAUTHORIZED', message: 'Authentication failed' };
      }
    }

    const data = await response.json();

    if (!response.ok) {
      const error = data as ApiError;
      throw error;
    }

    return data as T;
  }

  async request<T>(
    method: HttpMethod,
    path: string,
    body?: unknown,
    options: RequestConfig = {}
  ): Promise<T> {
    const url = new URL(getApiUrl(path));

    if (options.params) {
      Object.entries(options.params).forEach(([key, value]) => {
        url.searchParams.append(key, String(value));
      });
    }

    const headers = await this.getHeaders(options.headers);

    const fetchOptions: RequestInit = {
      method,
      headers,
      credentials: options.withCredentials ? 'include' : 'same-origin',
    };

    if (body && method !== 'GET') {
      fetchOptions.body = JSON.stringify(body);
    }

    const controller = new AbortController();
    const timeoutId = setTimeout(
      () => controller.abort(),
      options.timeout || this.timeout
    );
    fetchOptions.signal = controller.signal;

    try {
      const response = await fetch(url.toString(), fetchOptions);
      return this.handleResponse<T>(response);
    } finally {
      clearTimeout(timeoutId);
    }
  }

  get<T>(path: string, options?: RequestConfig): Promise<T> {
    return this.request<T>('GET', path, undefined, options);
  }

  post<T>(path: string, body?: unknown, options?: RequestConfig): Promise<T> {
    return this.request<T>('POST', path, body, options);
  }

  put<T>(path: string, body?: unknown, options?: RequestConfig): Promise<T> {
    return this.request<T>('PUT', path, body, options);
  }

  patch<T>(path: string, body?: unknown, options?: RequestConfig): Promise<T> {
    return this.request<T>('PATCH', path, body, options);
  }

  delete<T>(path: string, options?: RequestConfig): Promise<T> {
    return this.request<T>('DELETE', path, undefined, options);
  }
}

export const apiClient = new ApiClient();
export default apiClient;
