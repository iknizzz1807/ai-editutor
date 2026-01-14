// src/js/services/user.js - User service

import { apiClient } from '../api/client.js';
import { EventEmitter } from '../utils/events.js';

class UserService extends EventEmitter {
  constructor() {
    super();
    this.cache = new Map();
    this.cacheTimeout = 5 * 60 * 1000; // 5 minutes
  }

  async getUsers(params = {}) {
    const response = await apiClient.get('/users', params);
    return {
      users: response.users,
      total: response.total,
      page: response.page,
      pageSize: response.page_size,
      totalPages: response.total_pages,
    };
  }

  async getUser(id, useCache = true) {
    if (useCache && this.cache.has(id)) {
      const cached = this.cache.get(id);
      if (Date.now() - cached.timestamp < this.cacheTimeout) {
        return cached.data;
      }
    }

    const user = await apiClient.get(`/users/${id}`);
    this.cache.set(id, { data: user, timestamp: Date.now() });
    return user;
  }

  async createUser(userData) {
    const user = await apiClient.post('/users', userData);
    this.emit('userCreated', user);
    return user;
  }

  // Q: How should we implement optimistic updates for better UX?
  async updateUser(id, userData) {
    const user = await apiClient.patch(`/users/${id}`, userData);
    this.cache.set(id, { data: user, timestamp: Date.now() });
    this.emit('userUpdated', user);
    return user;
  }

  async deleteUser(id) {
    await apiClient.delete(`/users/${id}`);
    this.cache.delete(id);
    this.emit('userDeleted', id);
  }

  async searchUsers(query, limit = 20) {
    return apiClient.get('/users/search', { q: query, limit });
  }

  async activateUser(id) {
    const user = await apiClient.post(`/users/${id}/activate`);
    this.cache.set(id, { data: user, timestamp: Date.now() });
    this.emit('userActivated', user);
    return user;
  }

  async suspendUser(id, reason, durationDays = null) {
    const user = await apiClient.post(`/users/${id}/suspend`, {
      reason,
      duration_days: durationDays,
    });
    this.cache.set(id, { data: user, timestamp: Date.now() });
    this.emit('userSuspended', user);
    return user;
  }

  async getStats() {
    return apiClient.get('/users/stats');
  }

  // Address management
  async getUserAddresses(userId) {
    return apiClient.get(`/users/${userId}/addresses`);
  }

  async addUserAddress(userId, address) {
    return apiClient.post(`/users/${userId}/addresses`, address);
  }

  async updateUserAddress(userId, addressId, address) {
    return apiClient.patch(`/users/${userId}/addresses/${addressId}`, address);
  }

  async deleteUserAddress(userId, addressId) {
    return apiClient.delete(`/users/${userId}/addresses/${addressId}`);
  }

  async setDefaultAddress(userId, addressId) {
    return apiClient.post(`/users/${userId}/addresses/${addressId}/set-default`);
  }

  clearCache() {
    this.cache.clear();
  }

  invalidateCache(id) {
    this.cache.delete(id);
  }
}

export const userService = new UserService();
