// src/lib/api/client.ts - API client with interceptors

import type { ApiError } from '$lib/types';

interface RequestConfig extends RequestInit {
  skipAuth?: boolean;
  retryCount?: number;
}

// Q: How should we implement request deduplication for identical concurrent requests in SvelteKit?
class ApiClient {
  private baseUrl: string;
  private accessToken: string | null = null;
  private refreshToken: string | null = null;
  private refreshPromise: Promise<string> | null = null;
  private pendingRequests: Map<string, Promise<Response>> = new Map();

  constructor(baseUrl: string = '/api') {
    this.baseUrl = baseUrl;
  }

  setTokens(accessToken: string, refreshToken: string): void {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  clearTokens(): void {
    this.accessToken = null;
    this.refreshToken = null;
  }

  private async refreshAccessToken(): Promise<string> {
    if (this.refreshPromise) {
      return this.refreshPromise;
    }

    this.refreshPromise = (async () => {
      try {
        const response = await fetch(`${this.baseUrl}/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refreshToken: this.refreshToken }),
        });

        if (!response.ok) {
          throw new Error('Token refresh failed');
        }

        const data = await response.json();
        this.accessToken = data.accessToken;
        this.refreshToken = data.refreshToken;

        return data.accessToken;
      } finally {
        this.refreshPromise = null;
      }
    })();

    return this.refreshPromise;
  }

  private getRequestKey(url: string, method: string, body?: string): string {
    return `${method}:${url}:${body || ''}`;
  }

  async request<T>(
    endpoint: string,
    config: RequestConfig = {}
  ): Promise<T> {
    const { skipAuth = false, retryCount = 0, ...fetchConfig } = config;
    const url = `${this.baseUrl}${endpoint}`;

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(fetchConfig.headers as Record<string, string>),
    };

    if (!skipAuth && this.accessToken) {
      headers['Authorization'] = `Bearer ${this.accessToken}`;
    }

    const requestKey = this.getRequestKey(
      url,
      fetchConfig.method || 'GET',
      fetchConfig.body as string
    );

    // Deduplicate GET requests
    if (fetchConfig.method === 'GET' || !fetchConfig.method) {
      const pending = this.pendingRequests.get(requestKey);
      if (pending) {
        const response = await pending;
        return response.clone().json();
      }
    }

    const requestPromise = fetch(url, { ...fetchConfig, headers });

    if (fetchConfig.method === 'GET' || !fetchConfig.method) {
      this.pendingRequests.set(requestKey, requestPromise);
    }

    try {
      const response = await requestPromise;

      if (response.status === 401 && !skipAuth && retryCount < 1) {
        await this.refreshAccessToken();
        return this.request<T>(endpoint, { ...config, retryCount: retryCount + 1 });
      }

      if (!response.ok) {
        const error: ApiError = await response.json();
        throw error;
      }

      return response.json();
    } finally {
      this.pendingRequests.delete(requestKey);
    }
  }

  get<T>(endpoint: string, config?: RequestConfig): Promise<T> {
    return this.request<T>(endpoint, { ...config, method: 'GET' });
  }

  post<T>(endpoint: string, data?: unknown, config?: RequestConfig): Promise<T> {
    return this.request<T>(endpoint, {
      ...config,
      method: 'POST',
      body: JSON.stringify(data),
    });
  }

  put<T>(endpoint: string, data?: unknown, config?: RequestConfig): Promise<T> {
    return this.request<T>(endpoint, {
      ...config,
      method: 'PUT',
      body: JSON.stringify(data),
    });
  }

  delete<T>(endpoint: string, config?: RequestConfig): Promise<T> {
    return this.request<T>(endpoint, { ...config, method: 'DELETE' });
  }
}

export const apiClient = new ApiClient();
