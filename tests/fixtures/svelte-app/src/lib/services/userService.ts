// src/lib/services/userService.ts - User management service

import { apiClient } from '$lib/api/client';
import type { User, UserFilters, PaginatedResponse, UserRole, UserStatus } from '$lib/types';

interface GetUsersParams extends UserFilters {
  page?: number;
  pageSize?: number;
  sortBy?: keyof User;
  sortOrder?: 'asc' | 'desc';
}

// Q: How should we implement server-side pagination with SvelteKit load functions and URL params?
class UserService {
  async getUsers(params: GetUsersParams = {}): Promise<PaginatedResponse<User>> {
    const searchParams = new URLSearchParams();

    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== null && value !== '') {
        searchParams.append(key, String(value));
      }
    });

    const queryString = searchParams.toString();
    const endpoint = `/users${queryString ? `?${queryString}` : ''}`;

    return apiClient.get<PaginatedResponse<User>>(endpoint);
  }

  async getUser(id: string): Promise<User> {
    return apiClient.get<User>(`/users/${id}`);
  }

  async createUser(data: {
    email: string;
    username: string;
    password: string;
    role?: UserRole;
    firstName?: string;
    lastName?: string;
  }): Promise<User> {
    return apiClient.post<User>('/users', data);
  }

  async updateUser(
    id: string,
    data: {
      username?: string;
      role?: UserRole;
      status?: UserStatus;
      profile?: Partial<User['profile']>;
    }
  ): Promise<User> {
    return apiClient.put<User>(`/users/${id}`, data);
  }

  async deleteUser(id: string): Promise<void> {
    await apiClient.delete(`/users/${id}`);
  }

  async bulkUpdateStatus(userIds: string[], status: UserStatus): Promise<User[]> {
    return apiClient.post<User[]>('/users/bulk/status', { userIds, status });
  }

  async bulkDelete(userIds: string[]): Promise<void> {
    await apiClient.post('/users/bulk/delete', { userIds });
  }

  async exportUsers(filters: UserFilters = {}): Promise<Blob> {
    const searchParams = new URLSearchParams();

    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined && value !== null && value !== '') {
        searchParams.append(key, String(value));
      }
    });

    const queryString = searchParams.toString();
    const endpoint = `/users/export${queryString ? `?${queryString}` : ''}`;

    const response = await fetch(`/api${endpoint}`, {
      headers: {
        Authorization: `Bearer ${localStorage.getItem('accessToken')}`,
      },
    });

    if (!response.ok) {
      throw new Error('Export failed');
    }

    return response.blob();
  }

  async importUsers(file: File): Promise<{ imported: number; failed: number }> {
    const formData = new FormData();
    formData.append('file', file);

    const response = await fetch('/api/users/import', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${localStorage.getItem('accessToken')}`,
      },
      body: formData,
    });

    if (!response.ok) {
      throw new Error('Import failed');
    }

    return response.json();
  }
}

export const userService = new UserService();
