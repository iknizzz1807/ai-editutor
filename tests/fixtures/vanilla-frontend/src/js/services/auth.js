// src/js/services/auth.js - Authentication service

import { apiClient } from '../api/client.js';
import { storage } from '../utils/storage.js';
import { EventEmitter } from '../utils/events.js';

class AuthService extends EventEmitter {
  constructor() {
    super();
    this.user = null;
    this.isAuthenticated = false;
    this.init();
  }

  init() {
    // Check for existing session
    const token = storage.get('access_token');
    if (token) {
      this.loadCurrentUser();
    }
  }

  // Q: How should we handle authentication state across multiple browser tabs?
  async login(email, password) {
    try {
      const response = await apiClient.post('/auth/login', { email, password });

      storage.set('access_token', response.access_token);
      storage.set('refresh_token', response.refresh_token);

      this.user = response.user;
      this.isAuthenticated = true;

      this.emit('login', this.user);
      this.emit('authChange', { isAuthenticated: true, user: this.user });

      return response.user;
    } catch (error) {
      this.emit('loginError', error);
      throw error;
    }
  }

  async register(userData) {
    try {
      const response = await apiClient.post('/auth/register', userData);

      // Auto-login after registration
      storage.set('access_token', response.access_token);
      storage.set('refresh_token', response.refresh_token);

      this.user = response.user;
      this.isAuthenticated = true;

      this.emit('register', this.user);
      this.emit('authChange', { isAuthenticated: true, user: this.user });

      return response.user;
    } catch (error) {
      this.emit('registerError', error);
      throw error;
    }
  }

  async logout() {
    try {
      await apiClient.post('/auth/logout', {});
    } catch {
      // Ignore logout API errors
    } finally {
      this.clearSession();
    }
  }

  clearSession() {
    storage.remove('access_token');
    storage.remove('refresh_token');
    this.user = null;
    this.isAuthenticated = false;
    this.emit('logout');
    this.emit('authChange', { isAuthenticated: false, user: null });
  }

  async loadCurrentUser() {
    try {
      const user = await apiClient.get('/auth/me');
      this.user = user;
      this.isAuthenticated = true;
      this.emit('authChange', { isAuthenticated: true, user: this.user });
      return user;
    } catch {
      this.clearSession();
      return null;
    }
  }

  async updateProfile(profileData) {
    const user = await apiClient.patch('/users/me/profile', profileData);
    this.user = { ...this.user, ...user };
    this.emit('profileUpdate', this.user);
    return this.user;
  }

  async changePassword(currentPassword, newPassword) {
    await apiClient.post('/auth/change-password', {
      current_password: currentPassword,
      new_password: newPassword,
    });
    this.emit('passwordChange');
  }

  async requestPasswordReset(email) {
    await apiClient.post('/auth/forgot-password', { email });
  }

  async resetPassword(token, newPassword) {
    await apiClient.post('/auth/reset-password', {
      token,
      password: newPassword,
    });
  }

  async verifyEmail(token) {
    const response = await apiClient.post('/auth/verify-email', { token });
    if (this.user) {
      this.user.email_verified = true;
      this.emit('emailVerified', this.user);
    }
    return response;
  }

  getUser() {
    return this.user;
  }

  getIsAuthenticated() {
    return this.isAuthenticated;
  }

  hasRole(role) {
    return this.user?.role === role;
  }

  isAdmin() {
    return this.hasRole('admin');
  }
}

export const authService = new AuthService();
