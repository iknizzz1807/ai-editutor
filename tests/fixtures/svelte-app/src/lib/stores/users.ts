// src/lib/stores/users.ts - Users store with pagination

import { writable, derived } from 'svelte/store';
import { userService } from '$lib/services/userService';
import type { User, UserFilters, UserStatus } from '$lib/types';

interface UsersState {
  users: User[];
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
  filters: UserFilters;
  isLoading: boolean;
  error: string | null;
  selectedIds: Set<string>;
}

const initialState: UsersState = {
  users: [],
  total: 0,
  page: 1,
  pageSize: 20,
  totalPages: 0,
  filters: {},
  isLoading: false,
  error: null,
  selectedIds: new Set(),
};

// Q: How should we implement optimistic updates with rollback for bulk operations in Svelte stores?
function createUsersStore() {
  const { subscribe, set, update } = writable<UsersState>(initialState);

  async function fetchUsers(): Promise<void> {
    update((state) => ({ ...state, isLoading: true, error: null }));

    try {
      let currentState: UsersState;
      const unsubscribe = subscribe((state) => (currentState = state));
      unsubscribe();

      const response = await userService.getUsers({
        ...currentState!.filters,
        page: currentState!.page,
        pageSize: currentState!.pageSize,
      });

      update((state) => ({
        ...state,
        users: response.data,
        total: response.total,
        totalPages: response.totalPages,
        isLoading: false,
      }));
    } catch (error) {
      update((state) => ({
        ...state,
        isLoading: false,
        error: error instanceof Error ? error.message : 'Failed to fetch users',
      }));
    }
  }

  function setFilter<K extends keyof UserFilters>(
    key: K,
    value: UserFilters[K]
  ): void {
    update((state) => ({
      ...state,
      filters: { ...state.filters, [key]: value },
      page: 1,
    }));
    fetchUsers();
  }

  function clearFilters(): void {
    update((state) => ({
      ...state,
      filters: {},
      page: 1,
    }));
    fetchUsers();
  }

  function setPage(page: number): void {
    update((state) => ({ ...state, page }));
    fetchUsers();
  }

  function toggleSelection(userId: string): void {
    update((state) => {
      const newSelected = new Set(state.selectedIds);
      if (newSelected.has(userId)) {
        newSelected.delete(userId);
      } else {
        newSelected.add(userId);
      }
      return { ...state, selectedIds: newSelected };
    });
  }

  function selectAll(): void {
    update((state) => ({
      ...state,
      selectedIds: new Set(state.users.map((u) => u.id)),
    }));
  }

  function clearSelection(): void {
    update((state) => ({
      ...state,
      selectedIds: new Set(),
    }));
  }

  async function deleteUser(userId: string): Promise<void> {
    let previousUsers: User[];

    update((state) => {
      previousUsers = state.users;
      return {
        ...state,
        users: state.users.filter((u) => u.id !== userId),
        total: state.total - 1,
      };
    });

    try {
      await userService.deleteUser(userId);
    } catch (error) {
      update((state) => ({
        ...state,
        users: previousUsers,
        total: state.total + 1,
        error: error instanceof Error ? error.message : 'Failed to delete user',
      }));
      throw error;
    }
  }

  async function bulkUpdateStatus(status: UserStatus): Promise<void> {
    let previousUsers: User[];
    let selectedIds: string[];

    update((state) => {
      previousUsers = state.users;
      selectedIds = Array.from(state.selectedIds);
      return {
        ...state,
        users: state.users.map((u) =>
          state.selectedIds.has(u.id) ? { ...u, status } : u
        ),
      };
    });

    try {
      await userService.bulkUpdateStatus(selectedIds!, status);
      clearSelection();
    } catch (error) {
      update((state) => ({
        ...state,
        users: previousUsers!,
        error: error instanceof Error ? error.message : 'Failed to update users',
      }));
      throw error;
    }
  }

  async function bulkDelete(): Promise<void> {
    let previousUsers: User[];
    let previousTotal: number;
    let selectedIds: string[];

    update((state) => {
      previousUsers = state.users;
      previousTotal = state.total;
      selectedIds = Array.from(state.selectedIds);
      return {
        ...state,
        users: state.users.filter((u) => !state.selectedIds.has(u.id)),
        total: state.total - state.selectedIds.size,
        selectedIds: new Set(),
      };
    });

    try {
      await userService.bulkDelete(selectedIds!);
    } catch (error) {
      update((state) => ({
        ...state,
        users: previousUsers!,
        total: previousTotal!,
        selectedIds: new Set(selectedIds!),
        error: error instanceof Error ? error.message : 'Failed to delete users',
      }));
      throw error;
    }
  }

  return {
    subscribe,
    fetchUsers,
    setFilter,
    clearFilters,
    setPage,
    toggleSelection,
    selectAll,
    clearSelection,
    deleteUser,
    bulkUpdateStatus,
    bulkDelete,
  };
}

export const usersStore = createUsersStore();

export const users = derived(usersStore, ($state) => $state.users);
export const totalUsers = derived(usersStore, ($state) => $state.total);
export const currentPage = derived(usersStore, ($state) => $state.page);
export const totalPages = derived(usersStore, ($state) => $state.totalPages);
export const usersLoading = derived(usersStore, ($state) => $state.isLoading);
export const usersError = derived(usersStore, ($state) => $state.error);
export const selectedUserIds = derived(usersStore, ($state) => $state.selectedIds);
export const hasSelection = derived(usersStore, ($state) => $state.selectedIds.size > 0);
