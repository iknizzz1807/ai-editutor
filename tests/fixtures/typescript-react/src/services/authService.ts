// Authentication service
import { User } from '../types/user';
import { apiClient } from './apiClient';

interface LoginResponse {
  user: User;
  accessToken: string;
  refreshToken: string;
}

class AuthService {
  private tokenKey = 'auth_token';
  private refreshKey = 'refresh_token';

  async login(email: string, password: string): Promise<User> {
    const response = await apiClient.post<LoginResponse>('/auth/login', {
      email,
      password,
    });

    this.setTokens(response.accessToken, response.refreshToken);
    return response.user;
  }

  async logout(): Promise<void> {
    try {
      await apiClient.post('/auth/logout');
    } finally {
      this.clearTokens();
    }
  }

  async getCurrentUser(): Promise<User | null> {
    const token = this.getAccessToken();
    if (!token) return null;

    try {
      return await apiClient.get<User>('/auth/me');
    } catch {
      return null;
    }
  }

  async refreshToken(): Promise<void> {
    const refreshToken = this.getRefreshToken();
    if (!refreshToken) {
      throw new Error('No refresh token');
    }

    const response = await apiClient.post<LoginResponse>('/auth/refresh', {
      refreshToken,
    });

    this.setTokens(response.accessToken, response.refreshToken);
  }

  getAccessToken(): string | null {
    return localStorage.getItem(this.tokenKey);
  }

  private getRefreshToken(): string | null {
    return localStorage.getItem(this.refreshKey);
  }

  private setTokens(accessToken: string, refreshToken: string): void {
    localStorage.setItem(this.tokenKey, accessToken);
    localStorage.setItem(this.refreshKey, refreshToken);
  }

  private clearTokens(): void {
    localStorage.removeItem(this.tokenKey);
    localStorage.removeItem(this.refreshKey);
  }
}

export const authService = new AuthService();
