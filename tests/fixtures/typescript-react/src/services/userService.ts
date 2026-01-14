// User service
import { User, CreateUserDTO, UpdateUserDTO, UserFilters } from '../types/user';
import { apiClient } from './apiClient';

interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
}

class UserService {
  async getUsers(filters?: UserFilters): Promise<PaginatedResponse<User>> {
    const params = new URLSearchParams();
    if (filters?.role) params.set('role', filters.role);
    if (filters?.search) params.set('search', filters.search);
    if (filters?.page) params.set('page', String(filters.page));
    if (filters?.limit) params.set('limit', String(filters.limit));

    const query = params.toString();
    return apiClient.get<PaginatedResponse<User>>(`/users${query ? `?${query}` : ''}`);
  }

  async getUserById(id: string): Promise<User> {
    return apiClient.get<User>(`/users/${id}`);
  }

  async createUser(data: CreateUserDTO): Promise<User> {
    return apiClient.post<User>('/users', data);
  }

  async updateUser(id: string, data: UpdateUserDTO): Promise<User> {
    return apiClient.put<User>(`/users/${id}`, data);
  }

  async deleteUser(id: string): Promise<void> {
    await apiClient.delete(`/users/${id}`);
  }
}

export const userService = new UserService();
