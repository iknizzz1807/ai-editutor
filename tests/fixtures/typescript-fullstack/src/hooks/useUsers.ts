// hooks/useUsers.ts - User management hook

import { useState, useCallback, useEffect } from 'react';
import userService from '../services/userService';
import {
  User,
  UserResponse,
  UserListResponse,
  CreateUserDTO,
  UpdateUserDTO,
  UserFilters,
} from '../types/user';
import { PaginationParams } from '../types/api';

interface UseUsersState {
  users: UserResponse[];
  selectedUser: User | null;
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
  isLoading: boolean;
  error: string | null;
}

interface UseUsersReturn extends UseUsersState {
  fetchUsers: (filters?: UserFilters, pagination?: PaginationParams) => Promise<void>;
  fetchUser: (id: string) => Promise<void>;
  createUser: (data: CreateUserDTO) => Promise<User>;
  updateUser: (id: string, data: UpdateUserDTO) => Promise<User>;
  deleteUser: (id: string) => Promise<void>;
  searchUsers: (query: string) => Promise<UserResponse[]>;
  clearSelectedUser: () => void;
  clearError: () => void;
}

export function useUsers(initialFilters?: UserFilters): UseUsersReturn {
  const [state, setState] = useState<UseUsersState>({
    users: [],
    selectedUser: null,
    total: 0,
    page: 1,
    pageSize: 20,
    totalPages: 0,
    isLoading: false,
    error: null,
  });

  const fetchUsers = useCallback(
    async (filters?: UserFilters, pagination?: PaginationParams) => {
      setState((prev) => ({ ...prev, isLoading: true, error: null }));
      try {
        const response = await userService.getUsers(
          filters || initialFilters,
          pagination
        );
        setState((prev) => ({
          ...prev,
          users: response.users,
          total: response.total,
          page: response.page,
          pageSize: response.pageSize,
          totalPages: response.totalPages,
          isLoading: false,
        }));
      } catch (error: any) {
        setState((prev) => ({
          ...prev,
          isLoading: false,
          error: error.message || 'Failed to fetch users',
        }));
      }
    },
    [initialFilters]
  );

  const fetchUser = useCallback(async (id: string) => {
    setState((prev) => ({ ...prev, isLoading: true, error: null }));
    try {
      const user = await userService.getUserById(id);
      setState((prev) => ({
        ...prev,
        selectedUser: user,
        isLoading: false,
      }));
    } catch (error: any) {
      setState((prev) => ({
        ...prev,
        isLoading: false,
        error: error.message || 'Failed to fetch user',
      }));
    }
  }, []);

  const createUser = useCallback(async (data: CreateUserDTO): Promise<User> => {
    setState((prev) => ({ ...prev, isLoading: true, error: null }));
    try {
      const user = await userService.createUser(data);
      // Refresh the list after creating
      await fetchUsers();
      return user;
    } catch (error: any) {
      setState((prev) => ({
        ...prev,
        isLoading: false,
        error: error.message || 'Failed to create user',
      }));
      throw error;
    }
  }, [fetchUsers]);

  // Q: How should optimistic updates be implemented here for better UX?
  const updateUser = useCallback(
    async (id: string, data: UpdateUserDTO): Promise<User> => {
      setState((prev) => ({ ...prev, isLoading: true, error: null }));
      try {
        const user = await userService.updateUser(id, data);
        setState((prev) => ({
          ...prev,
          users: prev.users.map((u) =>
            u.id === id ? { ...u, ...data } : u
          ),
          selectedUser: prev.selectedUser?.id === id
            ? { ...prev.selectedUser, ...data }
            : prev.selectedUser,
          isLoading: false,
        }));
        return user;
      } catch (error: any) {
        setState((prev) => ({
          ...prev,
          isLoading: false,
          error: error.message || 'Failed to update user',
        }));
        throw error;
      }
    },
    []
  );

  const deleteUser = useCallback(async (id: string) => {
    setState((prev) => ({ ...prev, isLoading: true, error: null }));
    try {
      await userService.deleteUser(id);
      setState((prev) => ({
        ...prev,
        users: prev.users.filter((u) => u.id !== id),
        selectedUser: prev.selectedUser?.id === id ? null : prev.selectedUser,
        total: prev.total - 1,
        isLoading: false,
      }));
    } catch (error: any) {
      setState((prev) => ({
        ...prev,
        isLoading: false,
        error: error.message || 'Failed to delete user',
      }));
      throw error;
    }
  }, []);

  const searchUsers = useCallback(async (query: string): Promise<UserResponse[]> => {
    try {
      return await userService.searchUsers(query);
    } catch (error) {
      return [];
    }
  }, []);

  const clearSelectedUser = useCallback(() => {
    setState((prev) => ({ ...prev, selectedUser: null }));
  }, []);

  const clearError = useCallback(() => {
    setState((prev) => ({ ...prev, error: null }));
  }, []);

  // Initial fetch
  useEffect(() => {
    fetchUsers();
  }, [fetchUsers]);

  return {
    ...state,
    fetchUsers,
    fetchUser,
    createUser,
    updateUser,
    deleteUser,
    searchUsers,
    clearSelectedUser,
    clearError,
  };
}

export default useUsers;
