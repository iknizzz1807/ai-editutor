// services/userService.ts - User management service

import apiClient from '../api/client';
import { validateCreateUser } from '../utils/validation';
import {
  User,
  UserResponse,
  UserListResponse,
  CreateUserDTO,
  UpdateUserDTO,
  UserFilters,
} from '../types/user';
import { ApiResponse, PaginationParams, PaginatedResponse } from '../types/api';

class UserService {
  async getUsers(
    filters?: UserFilters,
    pagination?: PaginationParams
  ): Promise<UserListResponse> {
    const params: Record<string, string | number> = {};

    if (filters) {
      if (filters.role) params.role = filters.role;
      if (filters.status) params.status = filters.status;
      if (filters.search) params.search = filters.search;
      if (filters.createdAfter) params.createdAfter = filters.createdAfter.toISOString();
      if (filters.createdBefore) params.createdBefore = filters.createdBefore.toISOString();
    }

    if (pagination) {
      if (pagination.page) params.page = pagination.page;
      if (pagination.pageSize) params.pageSize = pagination.pageSize;
      if (pagination.sortBy) params.sortBy = pagination.sortBy;
      if (pagination.sortOrder) params.sortOrder = pagination.sortOrder;
    }

    const response = await apiClient.get<ApiResponse<UserListResponse>>(
      '/users',
      { params }
    );
    return response.data;
  }

  async getUserById(id: string): Promise<User> {
    const response = await apiClient.get<ApiResponse<User>>(`/users/${id}`);
    return response.data;
  }

  async getUserByUsername(username: string): Promise<User> {
    const response = await apiClient.get<ApiResponse<User>>(
      `/users/username/${username}`
    );
    return response.data;
  }

  async createUser(data: CreateUserDTO): Promise<User> {
    const validation = validateCreateUser(data);
    if (!validation.isValid) {
      throw { code: 'VALIDATION_ERROR', errors: validation.errors };
    }

    const response = await apiClient.post<ApiResponse<User>>('/users', data);
    return response.data;
  }

  // Q: How should we handle partial updates vs full updates in a type-safe way?
  async updateUser(id: string, data: UpdateUserDTO): Promise<User> {
    const response = await apiClient.patch<ApiResponse<User>>(
      `/users/${id}`,
      data
    );
    return response.data;
  }

  async deleteUser(id: string): Promise<void> {
    await apiClient.delete(`/users/${id}`);
  }

  async updateUserStatus(
    id: string,
    status: User['status']
  ): Promise<User> {
    const response = await apiClient.patch<ApiResponse<User>>(
      `/users/${id}/status`,
      { status }
    );
    return response.data;
  }

  async updateUserRole(id: string, role: User['role']): Promise<User> {
    const response = await apiClient.patch<ApiResponse<User>>(
      `/users/${id}/role`,
      { role }
    );
    return response.data;
  }

  async getUserStats(): Promise<{
    total: number;
    byRole: Record<string, number>;
    byStatus: Record<string, number>;
    newThisMonth: number;
  }> {
    const response = await apiClient.get<
      ApiResponse<{
        total: number;
        byRole: Record<string, number>;
        byStatus: Record<string, number>;
        newThisMonth: number;
      }>
    >('/users/stats');
    return response.data;
  }

  async searchUsers(query: string, limit: number = 10): Promise<UserResponse[]> {
    const response = await apiClient.get<ApiResponse<UserResponse[]>>(
      '/users/search',
      { params: { q: query, limit } }
    );
    return response.data;
  }

  async exportUsers(format: 'csv' | 'json' = 'json'): Promise<Blob> {
    const response = await fetch(
      `${apiClient['baseUrl']}/users/export?format=${format}`,
      {
        headers: {
          Authorization: `Bearer ${localStorage.getItem('auth_token')}`,
        },
      }
    );
    return response.blob();
  }
}

export const userService = new UserService();
export default userService;
