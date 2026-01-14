// services/authService.ts - Authentication service

import apiClient from '../api/client';
import { saveAuthTokens, clearAuthTokens, getRefreshToken } from '../utils/storage';
import { validateRegistration, validateChangePassword } from '../utils/validation';
import {
  LoginCredentials,
  RegisterData,
  AuthResponse,
  AuthTokens,
  PasswordResetRequest,
  PasswordResetConfirm,
  ChangePasswordRequest,
  TokenPayload,
} from '../types/auth';
import { User } from '../types/user';
import { ApiResponse } from '../types/api';

class AuthService {
  private tokenPayload: TokenPayload | null = null;

  async login(credentials: LoginCredentials): Promise<AuthResponse> {
    const response = await apiClient.post<ApiResponse<AuthResponse>>(
      '/auth/login',
      credentials
    );

    if (response.success) {
      saveAuthTokens(response.data.tokens);
      this.tokenPayload = this.decodeToken(response.data.tokens.accessToken);
    }

    return response.data;
  }

  async register(data: RegisterData): Promise<AuthResponse> {
    const validation = validateRegistration(data);
    if (!validation.isValid) {
      throw { code: 'VALIDATION_ERROR', errors: validation.errors };
    }

    const response = await apiClient.post<ApiResponse<AuthResponse>>(
      '/auth/register',
      {
        email: data.email,
        username: data.username,
        password: data.password,
      }
    );

    if (response.success) {
      saveAuthTokens(response.data.tokens);
      this.tokenPayload = this.decodeToken(response.data.tokens.accessToken);
    }

    return response.data;
  }

  async logout(): Promise<void> {
    const refreshToken = getRefreshToken();
    if (refreshToken) {
      try {
        await apiClient.post('/auth/logout', { refreshToken });
      } catch (error) {
        // Ignore logout errors, we'll clear tokens anyway
      }
    }
    clearAuthTokens();
    this.tokenPayload = null;
  }

  async requestPasswordReset(data: PasswordResetRequest): Promise<void> {
    await apiClient.post('/auth/password-reset/request', data);
  }

  async confirmPasswordReset(data: PasswordResetConfirm): Promise<void> {
    await apiClient.post('/auth/password-reset/confirm', data);
  }

  // Q: What security considerations should be made when implementing password change functionality?
  async changePassword(data: ChangePasswordRequest): Promise<void> {
    const validation = validateChangePassword(data);
    if (!validation.isValid) {
      throw { code: 'VALIDATION_ERROR', errors: validation.errors };
    }

    await apiClient.post('/auth/change-password', {
      currentPassword: data.currentPassword,
      newPassword: data.newPassword,
    });
  }

  async getCurrentUser(): Promise<User> {
    const response = await apiClient.get<ApiResponse<User>>('/auth/me');
    return response.data;
  }

  async verifyEmail(token: string): Promise<void> {
    await apiClient.post('/auth/verify-email', { token });
  }

  async resendVerificationEmail(): Promise<void> {
    await apiClient.post('/auth/resend-verification');
  }

  isAuthenticated(): boolean {
    return this.tokenPayload !== null && !this.isTokenExpired();
  }

  isTokenExpired(): boolean {
    if (!this.tokenPayload) return true;
    return Date.now() >= this.tokenPayload.exp * 1000;
  }

  getTokenPayload(): TokenPayload | null {
    return this.tokenPayload;
  }

  private decodeToken(token: string): TokenPayload {
    try {
      const base64Url = token.split('.')[1];
      const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
      const jsonPayload = decodeURIComponent(
        atob(base64)
          .split('')
          .map((c) => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2))
          .join('')
      );
      return JSON.parse(jsonPayload);
    } catch (error) {
      throw new Error('Invalid token');
    }
  }
}

export const authService = new AuthService();
export default authService;
