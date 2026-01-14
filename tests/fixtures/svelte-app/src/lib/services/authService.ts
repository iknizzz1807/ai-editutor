// src/lib/services/authService.ts - Authentication service

import { apiClient } from '$lib/api/client';
import type { User, LoginCredentials, RegisterData, AuthResponse } from '$lib/types';

// Q: How should we handle SSR authentication state in SvelteKit with cookies vs localStorage?
class AuthService {
  async login(credentials: LoginCredentials): Promise<AuthResponse> {
    const response = await apiClient.post<AuthResponse>(
      '/auth/login',
      credentials,
      { skipAuth: true }
    );

    apiClient.setTokens(response.accessToken, response.refreshToken);

    return response;
  }

  async register(data: RegisterData): Promise<AuthResponse> {
    const response = await apiClient.post<AuthResponse>(
      '/auth/register',
      data,
      { skipAuth: true }
    );

    apiClient.setTokens(response.accessToken, response.refreshToken);

    return response;
  }

  async logout(): Promise<void> {
    try {
      await apiClient.post('/auth/logout');
    } finally {
      apiClient.clearTokens();
    }
  }

  async getCurrentUser(): Promise<User> {
    return apiClient.get<User>('/auth/me');
  }

  async updateProfile(data: Partial<User['profile']>): Promise<User> {
    return apiClient.put<User>('/auth/profile', data);
  }

  async changePassword(currentPassword: string, newPassword: string): Promise<void> {
    await apiClient.post('/auth/change-password', {
      currentPassword,
      newPassword,
    });
  }

  async requestPasswordReset(email: string): Promise<void> {
    await apiClient.post('/auth/forgot-password', { email }, { skipAuth: true });
  }

  async resetPassword(token: string, newPassword: string): Promise<void> {
    await apiClient.post(
      '/auth/reset-password',
      { token, newPassword },
      { skipAuth: true }
    );
  }

  async verifyEmail(token: string): Promise<void> {
    await apiClient.post('/auth/verify-email', { token }, { skipAuth: true });
  }

  async resendVerificationEmail(): Promise<void> {
    await apiClient.post('/auth/resend-verification');
  }
}

export const authService = new AuthService();
