// src/services/userService.ts - User service

import { apiClient } from '@/api/client';
import type { User, UserFilters, PaginatedResponse } from '@/types/user';

export interface GetUsersParams extends UserFilters {
  page?: number;
  page_size?: number;
}

export const userService = {
  async getUsers(params: GetUsersParams = {}): Promise<PaginatedResponse<User>> {
    return apiClient.get<PaginatedResponse<User>>('/users', params);
  },

  async getUser(id: string): Promise<User> {
    return apiClient.get<User>(`/users/${id}`);
  },

  async createUser(data: Partial<User>): Promise<User> {
    return apiClient.post<User>('/users', data);
  },

  async updateUser(id: string, data: Partial<User>): Promise<User> {
    return apiClient.patch<User>(`/users/${id}`, data);
  },

  async deleteUser(id: string): Promise<void> {
    return apiClient.delete(`/users/${id}`);
  },

  async searchUsers(query: string, limit = 20): Promise<User[]> {
    return apiClient.get<User[]>('/users/search', { q: query, limit });
  },

  async activateUser(id: string): Promise<User> {
    return apiClient.post<User>(`/users/${id}/activate`);
  },

  async suspendUser(id: string, reason: string, durationDays?: number): Promise<User> {
    return apiClient.post<User>(`/users/${id}/suspend`, {
      reason,
      duration_days: durationDays,
    });
  },

  async getStats(): Promise<UserStats> {
    return apiClient.get<UserStats>('/users/stats');
  },
};

export interface UserStats {
  total: number;
  active: number;
  verified: number;
  newThisMonth: number;
  byRole: Record<string, number>;
  byStatus: Record<string, number>;
}
